package com.audiorelay.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

class MdnsRegistrar(private val context: Context) {

    companion object {
        private const val TAG = "MdnsRegistrar"
        private const val SERVICE_TYPE = "_audiorelay._tcp."
        private const val SERVICE_NAME = "AudioRelay"
    }

    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var isRegistered = false

    fun register(port: Int) {
        if (isRegistered) {
            Log.w(TAG, "Service already registered")
            return
        }

        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = SERVICE_NAME
            serviceType = SERVICE_TYPE
            setPort(port)
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.i(TAG, "mDNS service registered: ${info.serviceName} on port $port")
                isRegistered = true
            }

            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "mDNS registration failed: errorCode=$errorCode")
            }

            override fun onServiceUnregistered(info: NsdServiceInfo) {
                Log.i(TAG, "mDNS service unregistered: ${info.serviceName}")
                isRegistered = false
            }

            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "mDNS unregistration failed: errorCode=$errorCode")
            }
        }

        nsdManager?.registerService(
            serviceInfo,
            NsdManager.PROTOCOL_DNS_SD,
            registrationListener
        )
    }

    fun unregister() {
        if (!isRegistered && registrationListener == null) {
            return
        }

        try {
            registrationListener?.let { listener ->
                nsdManager?.unregisterService(listener)
            }
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Service was not registered", e)
        }

        registrationListener = null
        nsdManager = null
        isRegistered = false
    }
}
