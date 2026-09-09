/*
 * Food Nutrition Model
 * 食物营养数据模型
 */

import Foundation

// MARK: - Food Nutrition Response

struct FoodNutritionResponse: Codable, Sendable {
    let foods: [FoodItem]
    let totalCalories: Int
    let totalProtein: Double
    let totalFat: Double
    let totalCarbs: Double
    let healthScore: Int
    let suggestions: [String]

    enum CodingKeys: String, CodingKey {
        case foods
        case totalCalories = "total_calories"
        case totalProtein = "total_protein"
        case totalFat = "total_fat"
        case totalCarbs = "total_carbs"
        case healthScore = "health_score"
        case suggestions
    }
}

// MARK: - Food Item

struct FoodItem: Codable, Identifiable, Sendable {
    let id = UUID()
    let name: String
    let portion: String
    let calories: Int
    let protein: Double
    let fat: Double
    let carbs: Double
    let fiber: Double?
    let sugar: Double?
    let healthRating: String

    enum CodingKeys: String, CodingKey {
        case name
        case portion
        case calories
        case protein
        case fat
        case carbs
        case fiber
        case sugar
        case healthRating = "health_rating"
    }

    var healthRatingEmoji: String {
        switch healthRating {
        case "优秀": return "🟢"
        case "良好": return "🟡"
        case "一般": return "🟠"
        case "较差": return "🔴"
        default: return "⚪️"
        }
    }
}

// MARK: - Nutrition Summary

extension FoodNutritionResponse {
    func validate() throws {
        guard (0...100).contains(healthScore), totalCalories >= 0,
              [totalProtein, totalFat, totalCarbs].allSatisfy({ $0.isFinite && $0 >= 0 }),
              foods.allSatisfy({ food in
                  !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && food.calories >= 0 &&
                  [food.protein, food.fat, food.carbs, food.fiber ?? 0, food.sugar ?? 0].allSatisfy { $0.isFinite && $0 >= 0 }
              }) else { throw CocoaError(.coderInvalidValue) }
    }

    var formattedTotalCalories: String {
        "\(totalCalories) 千卡"
    }

    var formattedTotalProtein: String {
        String(format: "%.1f g", totalProtein)
    }

    var formattedTotalFat: String {
        String(format: "%.1f g", totalFat)
    }

    var formattedTotalCarbs: String {
        String(format: "%.1f g", totalCarbs)
    }

    var healthScoreColor: String {
        if healthScore >= 80 {
            return "green"
        } else if healthScore >= 60 {
            return "yellow"
        } else if healthScore >= 40 {
            return "orange"
        } else {
            return "red"
        }
    }

    var healthScoreText: String {
        if healthScore >= 80 {
            return "非常健康"
        } else if healthScore >= 60 {
            return "比较健康"
        } else if healthScore >= 40 {
            return "一般"
        } else {
            return "需要改善"
        }
    }
}

struct LeanEatRecord: Codable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case glasses, library }
    let id: UUID
    let timestamp: Date
    let source: Source
    let imagePath: String
    let nutrition: FoodNutritionResponse

    var title: String { nutrition.foods.map(\.name).joined(separator: "、") }
}
