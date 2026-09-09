#!/usr/bin/env python3
"""Build the home-only LOD from the current bundled USDZ (never the legacy generator).
Requires usd-core==26.8, meshoptimizer==0.2.30a0, numpy. Keeps source materials,
transforms, texture files and vertex attributes. Original full-screen asset is untouched.
"""
import ctypes
import json
from pathlib import Path
import tempfile
import subprocess
import zipfile
import numpy as np
import meshoptimizer
from pxr import Usd, UsdGeom, UsdUtils, Sdf

# 0.2.30a0 omits the ctypes signature for this exported C API.
from meshoptimizer.simplifier import lib
lib.meshopt_simplifyWithAttributes.restype = ctypes.c_size_t
lib.meshopt_simplifyWithAttributes.argtypes = [
    ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint), ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_float), ctypes.c_size_t, ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_float), ctypes.c_size_t, ctypes.POINTER(ctypes.c_float),
    ctypes.c_size_t, ctypes.POINTER(ctypes.c_ubyte), ctypes.c_size_t,
    ctypes.c_float, ctypes.c_uint, ctypes.POINTER(ctypes.c_float)]

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'CameraAccess/Resources/Models/Wayfarer.usdz'
DEST = SOURCE.with_name('WayfarerHome.usdz')


def main():
    report = []
    with tempfile.TemporaryDirectory(prefix='wayfarer-lod-') as directory:
        folder = Path(directory)
        with zipfile.ZipFile(SOURCE) as archive:
            archive.extractall(folder)
            root = folder / archive.namelist()[0]
        stage = Usd.Stage.Open(str(root))
        for prim in stage.Traverse():
            if not prim.IsA(UsdGeom.Mesh):
                continue
            mesh = UsdGeom.Mesh(prim)
            points = mesh.GetPointsAttr().Get()
            counts = mesh.GetFaceVertexCountsAttr().Get()
            assert all(n == 3 for n in counts), 'Expected triangulated source'
            assert not list(UsdGeom.Subset.GetAllGeomSubsets(mesh)), 'Subsets require face remapping'
            indices = np.asarray(mesh.GetFaceVertexIndicesAttr().Get(), dtype=np.uint32)
            positions = np.asarray(points, dtype=np.float32)
            primvars = UsdGeom.PrimvarsAPI(prim).GetPrimvars()
            attributes = []
            for pv in primvars:
                assert pv.GetInterpolation() not in ('faceVarying', 'uniform'), pv.GetName()
                if pv.GetBaseName() in ('st', 'normals') and pv.GetInterpolation() == 'vertex':
                    attributes.append(np.asarray(pv.ComputeFlattened(), dtype=np.float32))
            output = np.empty_like(indices)
            error = np.zeros(1, dtype=np.float32)
            attr = np.ascontiguousarray(np.concatenate(attributes, axis=1), dtype=np.float32)
            size = meshoptimizer.simplify_with_attributes(
                output, indices, positions, attr, np.full(attr.shape[1], 0.1, dtype=np.float32),
                target_index_count=max(24, int(len(indices) * 0.28) // 3 * 3),
                target_error=0.015, result_error=error)
            output = output[:size]
            used, remapped = np.unique(output, return_inverse=True)
            # Remap all vertex data, including skinning primvars. No guessed UVs.
            for pv in primvars:
                if pv.GetInterpolation() not in ('vertex', 'varying'):
                    continue
                if pv.IsIndexed():
                    values = pv.GetIndices()
                    pv.SetIndices(type(values)([values[int(i)] for i in used]))
                else:
                    values = pv.Get()
                    element_size = pv.GetElementSize()
                    assert len(values) == len(points) * element_size, pv.GetName()
                    pv.Set(type(values)([values[int(i) * element_size + j]
                                         for i in used for j in range(element_size)]))
            normals = mesh.GetNormalsAttr().Get()
            if normals:
                assert mesh.GetNormalsInterpolation() == 'vertex'
                mesh.GetNormalsAttr().Set(type(normals)([normals[int(i)] for i in used]))
            mesh.GetPointsAttr().Set(type(points)([points[int(i)] for i in used]))
            mesh.GetFaceVertexIndicesAttr().Set(remapped.tolist())
            mesh.GetFaceVertexCountsAttr().Set([3] * (size // 3))
            assert size > 0 and remapped.max() < len(used)
            report.append(dict(mesh=prim.GetName(), before=len(indices)//3, after=size//3,
                               verticesBefore=len(points), verticesAfter=len(used), error=float(error[0])))
        # Apple USDZ validation does not accept WebP; convert packaging format only.
        for prim in stage.Traverse():
            for attr in prim.GetAttributes():
                value = attr.Get()
                if isinstance(value, Sdf.AssetPath) and value.path.endswith('.webp'):
                    source = folder / value.path
                    target = source.with_suffix('.png')
                    if not target.exists():
                        subprocess.run(['sips', '-s', 'format', 'png', str(source), '--out', str(target)],
                                       check=True, stdout=subprocess.DEVNULL)
                    attr.Set(Sdf.AssetPath(str(target.relative_to(folder))))
        compact = folder / "WayfarerHome.usdc"
        stage.GetRootLayer().Export(str(compact))
        if DEST.exists():
            DEST.unlink()
        assert UsdUtils.CreateNewUsdzPackage(str(compact), str(DEST))
    totals = dict(trianglesBefore=sum(x['before'] for x in report),
                  trianglesAfter=sum(x['after'] for x in report),
                  verticesAfter=sum(x['verticesAfter'] for x in report),
                  sourceBytes=SOURCE.stat().st_size, lodBytes=DEST.stat().st_size, meshes=report)
    (ROOT / 'assets/wayfarer/home-lod-metrics.json').write_text(json.dumps(totals, indent=2)+'\n')
    print(json.dumps({k:v for k,v in totals.items() if k != 'meshes'}))

if __name__ == '__main__':
    main()
