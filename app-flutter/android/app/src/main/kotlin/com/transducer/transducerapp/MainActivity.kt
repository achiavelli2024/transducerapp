package com.transducer.transducerapp

import android.content.Context
import android.net.*
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "transducer/network"
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var boundNetwork: Network? = null

    // store the pending MethodChannel.Result to ensure we reply only once
    @Volatile
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> {
                        val ssid = call.argument<String>("ssid") // optional
                        bindToWifiNetwork(result, ssid)
                    }
                    "unbindNetwork" -> {
                        unbindNetwork(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun bindToWifiNetwork(result: MethodChannel.Result, ssid: String?) {
        val cm = connectivityManager ?: run {
            result.error("NO_CM", "ConnectivityManager not available", null)
            return
        }

        // if there's already a pending result, fail it (avoid multiple concurrent calls)
        if (pendingResult != null) {
            result.error("ALREADY_BOUNDING", "There is already a pending bind request", null)
            return
        }
        pendingResult = result

        // unregister previous callback if exists
        try {
            if (networkCallback != null) cm.unregisterNetworkCallback(networkCallback!!)
        } catch (e: Exception) {
            // ignore
        }

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                super.onAvailable(network)
                try {
                    val success = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        cm.bindProcessToNetwork(network)
                    } else {
                        ConnectivityManager.setProcessDefaultNetwork(network)
                        true
                    }
                    // reply only once
                    val r = pendingResult
                    if (r != null) {
                        pendingResult = null
                        // unregister callback to avoid multiple onAvailable calls delivering reply twice
                        try {
                            cm.unregisterNetworkCallback(this)
                            networkCallback = null
                        } catch (e: Exception) {
                            // ignore
                        }
                        if (success) {
                            boundNetwork = network
                            runOnUiThread { r.success("BOUND") }
                        } else {
                            runOnUiThread { r.error("BIND_FAIL", "bindProcessToNetwork returned false", null) }
                        }
                    } else {
                        // no pending result (already answered) - just capture network
                        boundNetwork = network
                    }
                } catch (e: Exception) {
                    val r = pendingResult
                    pendingResult = null
                    try { cm.unregisterNetworkCallback(this) } catch (_: Exception) {}
                    runOnUiThread { r?.error("EX", e.message, null) }
                }
            }

            override fun onUnavailable() {
                super.onUnavailable()
                val r = pendingResult
                pendingResult = null
                try { cm.unregisterNetworkCallback(this) } catch (_: Exception) {}
                runOnUiThread { r?.error("UNAVAILABLE", "Requested network unavailable", null) }
            }

            override fun onLost(network: Network) {
                super.onLost(network)
                if (boundNetwork != null && boundNetwork == network) {
                    boundNetwork = null
                }
            }
        }

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()

        try {
            cm.requestNetwork(request, networkCallback!!)
        } catch (e: Exception) {
            // clear pending and reply with error
            val r = pendingResult
            pendingResult = null
            try { cm.unregisterNetworkCallback(networkCallback!!) } catch (_: Exception) {}
            networkCallback = null
            result.error("REQ_FAIL", e.message, null)
        }
    }

    private fun unbindNetwork(result: MethodChannel.Result) {
        val cm = connectivityManager ?: run {
            result.error("NO_CM", "ConnectivityManager not available", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.bindProcessToNetwork(null)
            } else {
                ConnectivityManager.setProcessDefaultNetwork(null)
            }
            if (networkCallback != null) {
                try {
                    cm.unregisterNetworkCallback(networkCallback!!)
                } catch (e: Exception) {
                    // ignore
                }
                networkCallback = null
            }
            boundNetwork = null
            result.success("UNBOUND")
        } catch (e: Exception) {
            result.error("UNBIND_FAIL", e.message, null)
        }
    }
}