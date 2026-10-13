class_name RecipeData
extends Resource
## 制作配方：消耗若干材料，产出一件物品。
## ingredients / amounts 平行数组一一对应；配方文件放 data/recipes/，加配方不改代码。

@export var id := ""
@export var product: ItemData
@export var product_count := 1
@export var ingredients: Array[ItemData] = []
@export var amounts: Array[int] = []


## 产物总数（叠放材料的产物按数量算）。
func product_amount() -> int:
	return maxi(1, product_count)
