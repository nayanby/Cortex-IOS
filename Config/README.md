# Local Firebase configuration

The Apple app is registered in Firebase project `cortex-v1b` with bundle ID `com.cortex.notes` and nickname `Cortex Consumer iOS`.

Place its downloaded `GoogleService-Info.plist` in this directory. The file is ignored by Git and copied into the app when present. The startup code validates the project, bundle, sender and Apple app ID before initializing FirebaseCore. Missing or mismatched configuration does not connect to the backend.

Only FirebaseCore is wired at this stage. Authentication, entitlement/device policy, App Check, library downloads and user-data synchronization remain separate work. FirebaseCore initialization alone does not grant consumer access.

The unsigned cloud build can still compile and run offline reader tests without this file. Enabling Firebase in cloud-built apps will require supplying the config to the build environment.
