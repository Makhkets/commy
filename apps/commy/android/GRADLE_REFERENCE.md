# Что генерирует Flutter 3.44.8 по умолчанию

Не догадки, а вывод `flutter create --platforms=android` тем же SDK, которым
собирается проект. Версии плагинов Gradle — первое, на чём ломается собранный
руками Android-каркас, поэтому они зафиксированы здесь.

## Версии

| Что | Значение |
|---|---|
| Gradle wrapper | **9.1.0** (`gradle/wrapper/gradle-wrapper.properties`, уже на месте) |
| Android Gradle Plugin | **9.0.1** |
| Kotlin | **2.3.20** |
| `dev.flutter.flutter-plugin-loader` | 1.0.0 |
| Java / Kotlin target | 17 |

Обёртка (`gradlew`, `gradlew.bat`, `gradle/wrapper/`) уже скопирована — писать
её руками не надо, а качать другую версию не надо тем более.

## `settings.gradle.kts` — обязательная форма

`pluginManagement` читает путь к Flutter SDK из `local.properties` и подключает
`includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`. Без этого
`dev.flutter.flutter-gradle-plugin` не резолвится, и ошибка выглядит как
«плагин не найден в репозиториях», а не как «забыт includeBuild».

```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
include(":app")
```

## `gradle.properties` — два флага, которые легко потерять

```properties
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.newDsl=false
android.builtInKotlin=false
```

`android.newDsl` и `android.builtInKotlin` добавляет сам шаблон Flutter под AGP 9.
Убрать их — значит получить сборку, которая падает на несовместимости DSL.

## SDK-версии берутся у плагина Flutter

```kotlin
compileSdk = flutter.compileSdkVersion
minSdk     = flutter.minSdkVersion
targetSdk  = flutter.targetSdkVersion
ndkVersion = flutter.ndkVersion
```

**`minSdk` надо переопределить на 24.** Значение по умолчанию у Flutter ниже, а
`libbox.aar` собран с `-androidapi 24`; более низкий `minSdk` в манифесте
приложения даёт ошибку слияния манифестов, а не понятное сообщение.

**`ndkVersion` тоже надо переопределить — на `"28.0.13004108"`.** Соблазн
оставить `flutter.ndkVersion` понятен: мы линкуем **готовый** AAR, и Gradle
ничего нативного не компилирует. Но AGP всё равно проверяет, что заявленный NDK
установлен, и валит конфигурацию ещё до компиляции:

```
> NDK not configured. Download it with SDK manager.
  Preferred NDK version is '28.2.13676358'.
```

Значение у Flutter меняется от версии к версии, и сборка ломается на машине, где
стоит тот NDK, которым мы реально пользуемся. Пин ставит ядро и приложение на
одну версию — ту, которой `gomobile bind` собрал `libbox.aar`
([docs/13-libbox-reference.md](../../../docs/13-libbox-reference.md)).

## Чего в шаблоне нет и что надо дописать

- зависимость на `app/libs/libbox.aar` (файл уже лежит, 14 МБ, `arm64-v8a`);
- `applicationId` и `namespace` = `dev.commy.app` (шаблон ставит имя проекта);
- ABI splits + universal APK;
- release `signingConfig` из `key.properties` или переменных окружения, с
  откатом на debug-подпись, когда их нет — на этот откат опирается CI;
- всё содержимое `AndroidManifest.xml`: разрешения, `VpnService`, deep links.
