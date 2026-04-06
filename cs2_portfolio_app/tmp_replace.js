const fs = require('fs');
const files = [
    'c:/CS2_Inventory_App/cs2_portfolio_app/lib/inventory_page.dart',
    'c:/CS2_Inventory_App/cs2_portfolio_app/lib/market_page.dart',
    'c:/CS2_Inventory_App/cs2_portfolio_app/lib/main.dart',
    'c:/CS2_Inventory_App/cs2_portfolio_app/lib/services/inventory_service.dart'
];

const replacements = [
    ['bpPrice', 'skinportPrice'],
    ['bpPreviousPrice', 'skinportPreviousPrice'],
    ['lastBpPriceRefresh', 'lastSkinportPriceRefresh'],
    ['totalValueBp', 'totalValueSkinport'],
    ['updateAllPricesFromBP', 'updateAllPricesFromSkinport'],
    ['\\'bp\\'', '\\'skinport\\''],
    ['"BP"', '"Skinport"'],
    ['\\'BP\\'', '\\'Skinport\\''],
    ['"Backpack"', '"Skinport"'],
    ['\\'Backpack\\'', '\\'Skinport\\''],
    ['Backpack Updated', 'Skinport Updated'],
    ['BP Updated', 'Skinport Updated'],
    ['bp_price', 'skinport_price'],
    ['bp_previous_price', 'skinport_previous_price'],
    ['bp_value', 'skinport_value'],
    ['last_bp_price_refresh', 'last_skinport_price_refresh']
];

for (const f of files) {
    if (!fs.existsSync(f)) {
        console.log("File not found: " + f);
        continue;
    }
    let content = fs.readFileSync(f, 'utf-8');
    
    for (const [oldStr, newStr] of replacements) {
        content = content.split(oldStr).join(newStr);
    }
    
    fs.writeFileSync(f, content, 'utf-8');
}
console.log('Replacement complete.');
