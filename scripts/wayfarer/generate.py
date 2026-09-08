#!/usr/bin/env python3
"""Editable, dependency-free Wayfarer Gen 2 display mesh (metres, Y up, front +Z).
Reference: Meta shiny-black-green Gen 2 front, quarter and rear product photos.
Dimensions are proportional estimates, not manufacturer CAD. No photo textures.
Run from any cwd. Requires Apple's usdcat/usdzip/usdchecker on PATH to package.
"""
from pathlib import Path
import math, json, subprocess
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/wayfarer'
BUNDLE = ROOT / 'CameraAccess/Resources/Models'
PI = math.pi
meshes = []

def vecsub(a,b): return tuple(x-y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(v):
    n=math.sqrt(sum(x*x for x in v))
    return tuple(x/n for x in v) if n else (0,0,1)
def mesh(name, points, faces, material):
    normals=[[0,0,0] for _ in points]
    triangles=[]
    for face in faces:
        for j in range(1,len(face)-1):
            a,b,c=face[0],face[j],face[j+1]
            triangles.append((a,b,c))
            n=cross(vecsub(points[b],points[a]),vecsub(points[c],points[a]))
            for i in (a,b,c):
                for k in range(3): normals[i][k]+=n[k]
    meshes.append((name,points,triangles,[unit(n) for n in normals],material))

def curve(control, steps=10, closed=True):
    result=[]
    p=control if closed else [control[0]]+control+[control[-1]]
    count=len(p) if closed else len(p)-3
    for i in range(count):
        q=[p[(i+j-1)%len(p)] for j in range(4)] if closed else p[i:i+4]
        for s in range(steps):
            t=s/steps
            result.append(tuple(0.5*((2*q[1][k])+(-q[0][k]+q[2][k])*t+(2*q[0][k]-5*q[1][k]+4*q[2][k]-q[3][k])*t*t+(-q[0][k]+3*q[1][k]-3*q[2][k]+q[3][k])*t*t*t) for k in range(len(q[0]))))
    if not closed: result.append(control[-1])
    return result

def frontz(x): return .048-.006*(x/.075)**2
# Front-right rim; counterclockwise sampled silhouette has the characteristic tapered lower edge.
outline=curve([(9,18),(25,22),(46,23),(68,19),(66,5),(60,-17),(47,-24),(28,-23),(17,-17),(11,-2)])
outline=list(reversed([(x/1000,y/1000) for x,y in outline]))
N=len(outline)
for side,label in [(1,'Right'),(-1,'Left')]:
    outer=[(side*x,y) for x,y in outline]
    inner=[(side*(.038+(x-.038)*.80),-.001+(y+.001)*.77) for x,y in outline]
    points=[]; faces=[]; slices=16
    for j in range(slices):
        a=2*PI*j/slices
        t=.5+.5*math.copysign(abs(math.cos(a))**.38,math.cos(a))
        z=.0038*math.copysign(abs(math.sin(a))**.38,math.sin(a))
        for o,i in zip(outer,inner):
            x,y=(o[0]*(1-t)+i[0]*t,o[1]*(1-t)+i[1]*t)
            points.append((x,y,frontz(x)+z))
    for j in range(slices):
        for i in range(N):
            f=(j*N+i,j*N+(i+1)%N,((j+1)%slices)*N+(i+1)%N,((j+1)%slices)*N+i)
            faces.append(f if side==1 else f[::-1])
    mesh(label+'Rim',points,faces,'Frame')
    # Slightly domed thin lenses; each side is a real surface rather than a flat image.
    points=[]; faces=[]; rings=6
    center=(side*.038,-.001)
    for r in range(rings):
        t=(r+1)/rings
        for x,y in inner:
            xx=center[0]+(x-center[0])*t; yy=center[1]+(y-center[1])*t
            points.append((xx,yy,frontz(xx)+.0015*(1-t*t)))
    points.append((center[0],center[1],frontz(center[0])+.0015))
    for i in range(N): faces.append((rings*N,i,(i+1)%N))
    for r in range(rings-1):
        for i in range(N): faces.append((r*N+i,(r+1)*N+i,(r+1)*N+(i+1)%N,r*N+(i+1)%N))
    if side==-1: faces=[f[::-1] for f in faces]
    mesh(label+'Lens',points,faces,'Lens')

def tube(name, path, radii, material, steps=10):
    # Sweep elliptical rounded sections along a smooth centre line; local horizontal follows XZ.
    points=[];faces=[];count=len(path)
    for i,p in enumerate(path):
        tangent=unit(vecsub(path[min(i+1,count-1)],path[max(0,i-1)]))
        horizontal=unit(cross((0,1,0),tangent)); vertical=unit(cross(tangent,horizontal))
        rx,ry=radii[i]
        for j in range(steps):
            a=2*PI*j/steps
            points.append(tuple(p[k]+horizontal[k]*rx*math.cos(a)+vertical[k]*ry*math.sin(a) for k in range(3)))
    for i in range(count-1):
        for j in range(steps): faces.append((i*steps+j,i*steps+(j+1)%steps,(i+1)*steps+(j+1)%steps,(i+1)*steps+j))
    faces += [tuple(range(steps-1,-1,-1)),tuple((count-1)*steps+j for j in range(steps))]
    mesh(name,points,faces,material)

bridge=curve([(-.014,.016,.048),(-.008,.015,.049),(0,.012,.050),(.008,.015,.049),(.014,.016,.048)],6,False)
tube('Bridge',bridge,[(.004,.004)]*len(bridge),'Frame',16)
for side,label in [(1,'Right'),(-1,'Left')]:
    path=curve([(side*.065,.015,.044),(side*.071,.013,.030),(side*.071,.012,-.013),(side*.070,.008,-.052),(side*.067,-.004,-.080),(side*.064,-.014,-.088)],8,False)
    radii=[(.0035*(1-.42*i/(len(path)-1)),.008*(1-.65*i/(len(path)-1))) for i in range(len(path))]
    tube(label+'Temple',path,radii,'Frame',16)
    nose=curve([(side*.012,.004,.046),(side*.012,-.003,.039),(side*.015,-.010,.036)],6,False)
    tube(label+'NosePad',nose,[(.0025,.003)]*len(nose),'Frame',12)
    # Small metal hinge barrels visible from behind.
    tube(label+'Hinge',[(side*.065,.008,.038),(side*.065,.020,.038)],[(.0022,.0022)]*2,'Metal',16)
    # Recessed temple seam / touch strip, represented by separate narrow geometry.
    tube(label+'TouchStrip',[(side*.074,.017,.022),(side*.074,.016,-.008)],[(.00035,.0007)]*2,'Seam',8)

def disc(name,x,y,z,r,depth,material):
    points=[];faces=[];n=48
    for zz in [z-depth,z]:
        for i in range(n): points.append((x+r*math.cos(i*2*PI/n),y+r*math.sin(i*2*PI/n),zz))
    for i in range(n): faces.append((i,(i+1)%n,n+(i+1)%n,n+i))
    faces.append(tuple(range(n-1,-1,-1)));faces.append(tuple(n+i for i in range(n)))
    mesh(name,points,faces,material)
for side,label in [(1,'Indicator'),(-1,'Camera')]:
    x=side*.063;y=.015;z=frontz(x)+.0042
    disc(label+'Housing',x,y,z,.004,.002,'Seam')
    disc(label+'Bezel',x,y,z+.0003,.0032,.0005,'Metal')
    disc(label+'Glass',x,y,z+.0007,.00265,.0005,'Camera' if side==-1 else 'Indicator')
    if side==-1: disc('CameraAperture',x,y,z+.0009,.00125,.0002,'Seam')

materials={
 'Frame':((.009,.011,.014),.21,0,1),
 'Lens':((.085,.115,.055),.12,0,.78),
 'Metal':((.18,.19,.20),.24,.85,1),
 'Seam':((.002,.003,.004),.42,0,1),
 'Camera':((.018,.025,.045),.08,.25,1),
 'Indicator':((.17,.18,.16),.18,.05,1),
}
def arr(seq): return '['+', '.join(str(tuple(round(float(v),7) for v in p)) for p in seq)+']'
lines=['#usda 1.0','(defaultPrim = "Wayfarer"',' metersPerUnit = 1',' upAxis = "Y")','def Xform "Wayfarer" {',' def Scope "Materials" {']
for name,(color,rough,metal,opacity) in materials.items():
    lines += [f'  def Material "{name}" {{',f'   token outputs:surface.connect = </Wayfarer/Materials/{name}/Shader.outputs:surface>', '   def Shader "Shader" {','    uniform token info:id = "UsdPreviewSurface"',f'    color3f inputs:diffuseColor = {color}',f'    float inputs:roughness = {rough}',f'    float inputs:metallic = {metal}',f'    float inputs:opacity = {opacity}','    float inputs:ior = 1.5','    token outputs:surface','   }','  }']
lines+=[' }']
for name,points,faces,normals,mat in meshes:
    lines += [f' def Mesh "{name}" (prepend apiSchemas = ["MaterialBindingAPI"]) {{',f'  point3f[] points = {arr(points)}',f'  int[] faceVertexCounts = {[3]*len(faces)}',f'  int[] faceVertexIndices = {[i for f in faces for i in f]}',f'  normal3f[] normals = {arr(normals)} (interpolation = "vertex")','  uniform token subdivisionScheme = "none"','  uniform bool doubleSided = true',f'  rel material:binding = </Wayfarer/Materials/{mat}>',' }']
lines+=['}']
OUT.mkdir(parents=True,exist_ok=True); BUNDLE.mkdir(parents=True,exist_ok=True)
source=OUT/'wayfarer.usda'; source.write_text('\n'.join(lines)+'\n')
subprocess.run(['usdcat',str(source),'-o',str(OUT/'wayfarer.usdc')],check=True)
package=BUNDLE/'Wayfarer.usdz'
subprocess.run(['usdzip','--arkitAsset',str(OUT/'wayfarer.usdc'),str(package)],check=True)
subprocess.run(['usdchecker','--arkit',str(package)],check=True)
metrics={'vertices':sum(len(m[1]) for m in meshes),'triangles':sum(len(m[2]) for m in meshes),'meshes':len(meshes),'usdz_bytes':package.stat().st_size}
assert metrics['triangles'] <= 50000 and metrics['usdz_bytes'] <= 5*1024*1024
(OUT/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
print(metrics)
