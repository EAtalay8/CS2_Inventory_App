$files = @(
    "c:\CS2_Inventory_App\cs2_portfolio_app\lib\inventory_page.dart",
    "c:\CS2_Inventory_App\cs2_portfolio_app\lib\market_page.dart",
    "c:\CS2_Inventory_App\cs2_portfolio_app\lib\main.dart",
    "c:\CS2_Inventory_App\cs2_portfolio_app\lib\services\inventory_service.dart"
)

# Using ordered dictionary if possible, but standard is fine
$replacements = @(
    @("bpPrice", "skinportPrice"),
    @("bpPreviousPrice", "skinportPreviousPrice"),
    @("lastBpPriceRefresh", "lastSkinportPriceRefresh"),
    @("totalValueBp", "totalValueSkinport"),
    @("updateAllPricesFromBP", "updateAllPricesFromSkinport"),
    @("'bp'", "'skinport'"),
    @("""BP""", """Skinport"""),
    @("'BP'", "'Skinport'"),
    @("""Backpack""", """Skinport"""),
    @("'Backpack'", "'Skinport'"),
    @("Backpack Updated", "Skinport Updated"),
    @("BP Updated", "Skinport Updated"),
    @("bp_price", "skinport_price"),
    @("bp_previous_price", "skinport_previous_price"),
    @("bp_value", "skinport_value"),
    @("last_bp_price_refresh", "last_skinport_price_refresh")
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $content = Get-Content -Path $f -Raw
        foreach ($pair in $replacements) {
            $key = $pair[0]
            $value = $pair[1]
            $content = $content.Replace($key, $value)
        }
        Set-Content -Path $f -Value $content -Encoding UTF8
    }
}
Write-Output "Done"
