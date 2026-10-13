class_name Crafting
extends RefCounted
## 制作系统：加载 data/recipes/ 下的全部配方，检查材料、执行制作。
## 纯静态工具类，不进场景树。

const RECIPES_DIR := "res://data/recipes"


## 读取全部配方（按文件名排序，稳定顺序供 UI 与测试使用）。
static func load_recipes() -> Array[RecipeData]:
	var recipes: Array[RecipeData] = []
	var dir := DirAccess.open(RECIPES_DIR)
	if dir == null:
		return recipes
	var files: Array[String] = []
	for path in dir.get_files():
		# 编辑器里可能混入 .tres.import / .uid，只收资源本体。
		if path.ends_with(".tres") or path.ends_with(".tres.remap"):
			files.append(path.trim_suffix(".remap"))
	files.sort()
	for file in files:
		var res: Variant = load(RECIPES_DIR + "/" + file)
		if res is RecipeData:
			recipes.append(res)
	return recipes


## 背包中某材料是否足够。
static func has_enough(inventory: Inventory, recipe: RecipeData, index: int) -> bool:
	if index < 0 or index >= recipe.ingredients.size():
		return false
	var amount := recipe.amounts[index] if index < recipe.amounts.size() else 1
	return inventory.count_of(recipe.ingredients[index]) >= amount


## 是否所有材料都够。
static func can_craft(inventory: Inventory, recipe: RecipeData) -> bool:
	if inventory == null or recipe == null or recipe.product == null:
		return false
	for i in recipe.ingredients.size():
		if not has_enough(inventory, recipe, i):
			return false
	return true


## 缺料摘要文本（给 UI/测试）；材料全够时返回空串。
static func missing_text(inventory: Inventory, recipe: RecipeData) -> String:
	var parts: Array[String] = []
	for i in recipe.ingredients.size():
		var mat := recipe.ingredients[i]
		var need := recipe.amounts[i] if i < recipe.amounts.size() else 1
		var have := inventory.count_of(mat) if inventory != null else 0
		if have < need:
			parts.append("%s %d/%d" % [mat.display_name, have, need])
	return "缺 " + "、".join(parts)


## 执行制作：先放产物再扣料。产物放不下时不扣料直接拒绝；
## 产物只放下一部分则回滚，保证无半成品副作用。
static func craft(inventory: Inventory, recipe: RecipeData) -> bool:
	if not can_craft(inventory, recipe):
		return false
	var placed := 0
	for j in recipe.product_amount():
		if not inventory.add_item(recipe.product):
			break
		placed += 1
	if placed < recipe.product_amount():
		for j in placed:
			for i in inventory.slots.size():
				var placed_item := inventory.slots[i]
				if placed_item != null \
						and placed_item.resource_path == recipe.product.resource_path:
					inventory.remove_item(i)
					break
		return false
	for i in recipe.ingredients.size():
		var need := recipe.amounts[i] if i < recipe.amounts.size() else 1
		inventory.consume(recipe.ingredients[i], need)
	return true
