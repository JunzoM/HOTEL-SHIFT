from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
tests = r'''
let first = UUID(), second = UUID()
var data = Data()
assert(LaborBudgetSettings.value(for: first, data: data, legacy: 2600000) == 2600000)
data = LaborBudgetSettings.updating(100, for: first, data: data)!
assert(LaborBudgetSettings.value(for: first, data: data, legacy: 2600000) == 100)
assert(LaborBudgetSettings.value(for: second, data: data, legacy: 2600000) == 2600000)
data = LaborBudgetSettings.updating(200, for: second, data: data)!
assert(LaborBudgetSettings.value(for: first, data: data, legacy: 2600000) == 100)
assert(LaborBudgetSettings.value(for: second, data: data, legacy: 2600000) == 200)
assert(LaborBudgetSettings.updating(-1, for: first, data: data) == nil)
assert(LaborBudgetSettings.value(for: first, data: Data("bad".utf8), legacy: -1) == 0)
let valid: [(String, Int)] = [("0",0),("2600000",2600000),("2,600,000",2600000),
    ("２，６００，０００",2600000),("¥ 1,000",1000),("  ￥１０００ \n",1000),
    ("١٢٣",123),(String(Int.max),Int.max)]
for (text,value) in valid { assert(LaborBudgetSettings.parse(text) == value, text) }
let invalid = ["", " ", "-1", "+1", "−100", "abc100", "1.5", "1e3", "1/2", "1²", "⑩", "1,,000", "1000,000", "1,00", "1,", ",100", String(repeating:"9", count:1000)]
for text in invalid { assert(LaborBudgetSettings.parse(text) == nil, text) }
print("Budget: 32 migration, per-location isolation and input boundary checks passed")
'''
with tempfile.TemporaryDirectory(prefix='fixed555-budget-') as folder:
    script = Path(folder)/'budget.swift'
    script.write_text('import Foundation\n@main struct Runner { static func main() {\n'+tests+'\n} }\n')
    subprocess.run(['swiftc','-parse-as-library',str(root/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(script),'-o',str(Path(folder)/'test')],check=True)
    subprocess.run([str(Path(folder)/'test')],check=True)
