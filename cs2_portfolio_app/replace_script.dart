import 'dart:io';

void main() {
  final files = [
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\inventory_page.dart',
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\market_page.dart',
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\main.dart',
    r'c:\CS2_Inventory_App\cs2_portfolio_app\lib\services\inventory_service.dart'
  ];

  final replacements = {
    'bpPrice': 'skinportPrice',
    'bpPreviousPrice': 'skinportPreviousPrice',
    'lastBpPriceRefresh': 'lastSkinportPriceRefresh',
    'totalValueBp': 'totalValueSkinport',
    'updateAllPricesFromBP': 'updateAllPricesFromSkinport',
    "'bp'": "'skinport'",
    '"BP"': '"Skinport"',
    "'BP'": "'Skinport'",
    '"Backpack"': '"Skinport"',
    "'Backpack'": "'Skinport'",
    'Backpack Updated': 'Skinport Updated',
    'BP Updated': 'Skinport Updated',
    'bp_price': 'skinport_price',
    'bp_previous_price': 'skinport_previous_price',
    'bp_value': 'skinport_value',
    'last_bp_price_refresh': 'last_skinport_price_refresh',
  };

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();
    
    replacements.forEach((oldStr, newStr) {
      content = content.replaceAll(oldStr, newStr);
    });
    
    file.writeAsStringSync(content);
  }
  print("Done");
}
