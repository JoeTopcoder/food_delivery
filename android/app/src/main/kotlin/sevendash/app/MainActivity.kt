package sevendash.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Show the splash drawable (brand bg + centred icon) before Flutter
        // draws its first frame — eliminates the white flash on cold start.
        window.setBackgroundDrawable(
            resources.getDrawable(R.drawable.launch_background, theme)
        )
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        // Only forward intents that carry a real deep-link URI.
        // With launchMode="singleTop", Android calls onNewIntent on every
        // resume-from-launcher/recent-apps — those intents have no data URI.
        // The app_links plugin intercepts ALL onNewIntent calls and can fire
        // a spurious auth event that briefly signs the user out on warm resume.
        // Guarding here keeps deep links (Supabase OAuth, Stripe, PowerTranz)
        // working while ignoring benign resume intents.
        if (intent.data != null) {
            super.onNewIntent(intent)
        }
    }

}
