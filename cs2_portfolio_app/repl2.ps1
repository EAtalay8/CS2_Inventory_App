$f1 = "c:\CS2_Inventory_App\cs2_portfolio_app\lib\inventory_page.dart"
$f2 = "c:\CS2_Inventory_App\cs2_portfolio_app\lib\market_page.dart"
$f3 = "c:\CS2_Inventory_App\cs2_portfolio_app\lib\main.dart"
$f4 = "c:\CS2_Inventory_App\cs2_portfolio_app\lib\services\inventory_service.dart"
$files = @($f1, $f2, $f3, $f4)

foreach ($f in $files) {
    if (Test-Path $f) {
        $content = Get-Content -Path $f -Raw
        $content = $content.Replace('bpPrice', 'skinportPrice')
        $content = $content.Replace('bpPreviousPrice', 'skinportPreviousPrice')
        $content = $content.Replace('lastBpPriceRefresh', 'lastSkinportPriceRefresh')
        $content = $content.Replace('totalValueBp', 'totalValueSkinport')
        $content = $content.Replace('updateAllPricesFromBP', 'updateAllPricesFromSkinport')
        $content = $content.Replace('''bp''', '''skinport''')
        $content = $content.Replace('"BP"', '"Skinport"')
        $content = $content.Replace('''BP''', '''Skinport''')
        $content = $content.Replace('"Backpack"', '"Skinport"')
        $content = $content.Replace('''Backpack''', '''Skinport''')
        $content = $content.Replace('Backpack Updated', 'Skinport Updated')
        $content = $content.Replace('BP Updated', 'Skinport Updated')
        $content = $content.Replace('bp_price', 'skinport_price')
        $content = $content.Replace('bp_previous_price', 'skinport_previous_price')
        $content = $content.Replace('bp_value', 'skinport_value')
        $content = $content.Replace('last_bp_price_refresh', 'last_skinport_price_refresh')
        Set-Content -Path $f -Value $content -Encoding UTF8
    }
}
Write-Output "Done"
