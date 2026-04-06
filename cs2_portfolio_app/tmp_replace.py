import os

files = [
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\inventory_page.dart',
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\market_page.dart',
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\main.dart',
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\services\inventory_service.dart'
]

replacements = [
    ('bpPrice', 'skinportPrice'),
    ('bpPreviousPrice', 'skinportPreviousPrice'),
    ('lastBpPriceRefresh', 'lastSkinportPriceRefresh'),
    ('totalValueBp', 'totalValueSkinport'),
    ('activePriceSource == \'bp\'', 'activePriceSource == \'skinport\''),
    ('topMoversSource == \'bp\'', 'topMoversSource == \'skinport\''),
    ('marketPriceSource == \'bp\'', 'marketPriceSource == \'skinport\''),
    ('value: \'bp\'', 'value: \'skinport\''),
    ('updateAllPricesFromBP', 'updateAllPricesFromSkinport'),
    ('"BP"', '"Skinport"'),
    ('\'BP\'', '\'Skinport\''),
    ('"Backpack"', '"Skinport"'),
    ('\'Backpack\'', '\'Skinport\''),
    ('Backpack Updated', 'Skinport Updated'),
    ('BP Updated', 'Skinport Updated'),
    ('bp_price', 'skinport_price'),
    ('bp_previous_price', 'skinport_previous_price'),
    ('bp_value', 'skinport_value'),
    ('last_bp_price_refresh', 'last_skinport_price_refresh')
]

for f in files:
    if not os.path.exists(f):
        print(f"File not found: {f}")
        continue
    with open(f, 'r', encoding='utf-8') as file:
        content = file.read()
    
    for old, new in replacements:
        content = content.replace(old, new)
        
    with open(f, 'w', encoding='utf-8') as file:
        file.write(content)
print('Replacement complete.')
