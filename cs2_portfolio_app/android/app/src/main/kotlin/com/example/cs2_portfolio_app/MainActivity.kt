package com.example.cs2_portfolio_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.cs2portfolio/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCookies") {
                val url = call.argument<String>("url")
                if (url != null) {
                    val cookieManager = CookieManager.getInstance()
                    val cookies = cookieManager.getCookie(url)
                    result.success(cookies)
                } else {
                    result.error("INVALID_URL", "URL is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
