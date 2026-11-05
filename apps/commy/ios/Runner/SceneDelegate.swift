import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        for context in connectionOptions.urlContexts { (UIApplication.shared.delegate as? AppDelegate)?.receive(context.url) }
    }
    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts { (UIApplication.shared.delegate as? AppDelegate)?.receive(context.url) }
    }
}
