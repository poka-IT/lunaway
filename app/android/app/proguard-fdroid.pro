# F-Droid build: Google Play Services are left out (build.gradle.kts). The
# maplibre_gl plugin still compiles a Play Services location engine it only
# uses at high accuracy, which the app never asks for; its references to
# those classes are dead code here.
-dontwarn com.google.android.gms.**
