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

Пин обязан стоять **во всех** подпроектах, а не только в `:app`. Каждый
Flutter-плагин — отдельный Gradle-проект со своим `ndkVersion flutter.ndkVersion`,
и одного `:app` не хватает: сборка падает на `:jni`. В `build.gradle.kts` это
сделано через `subprojects { afterEvaluate { ... } }` — именно `afterEvaluate`,
потому что колбэк `plugins.withId` срабатывает **раньше**, чем блок `android { }`
самого подпроекта, и пин затирается тем самым значением, которое он должен был
заменить.

## `buildConfig` выключен по умолчанию

С AGP 8 генерация `BuildConfig` отключена. `CoreSetup` читает `BuildConfig.DEBUG`
(уровень логов ядра и дамп stderr), поэтому в `app/build.gradle.kts` нужно:

```kotlin
android {
    buildFeatures { buildConfig = true }
}
```

Без этого модуль просто не компилируется: три `Unresolved reference 'BuildConfig'`,
ни одно из которых не намекает на изменившийся дефолт Gradle.

## Классический Kotlin-плагин против встроенного в AGP 9

Самая дорогая ловушка этого набора зависимостей. AGP 9 умеет компилировать Kotlin
сам, и экосистема плагинов расколота ровно пополам:

| Плагин | Поведение на AGP 9 | Что ломается |
|---|---|---|
| `mobile_scanner` и другие | применяют `org.jetbrains.kotlin.android` **безусловно** | при `builtInKotlin=true` — жёсткая ошибка при применении `com.android.library` |
| `file_picker` 11 | детектит AGP 9 и **не применяет ничего** | при `builtInKotlin=false` его `src/main/kotlin` никто не компилирует |

Второй случай особенно неприятен: `:file_picker:compileDebugKotlin` вообще не
появляется в списке задач, библиотека собирается пустой, а падает всё через два
модуля и выглядит как битый pub-кэш:

```
GeneratedPluginRegistrant.java:19: error: cannot find symbol
    new com.mr.flutter.plugin.filepicker.FilePickerPlugin()
```

Выбранное решение: остаёмся на **классическом** плагине
(`android.builtInKotlin=false`, `android.newDsl=false`), а тем подпроектам,
которые от него отказались, применяем его руками в `build.gradle.kts`:

```kotlin
project.plugins.withId("com.android.library") {
    if (!project.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
        project.plugins.apply("org.jetbrains.kotlin.android")
    }
}
```

Обратный вариант (перейти на встроенный Kotlin и убрать плагин из `:app`)
проверен и **не работает**: на нём падают плагины из первой строки таблицы.
Когда экосистема доедет до AGP 9 целиком, это место надо будет упростить.

## Чего в шаблоне нет и что надо дописать

- зависимость на `app/libs/libbox.aar` (файл уже лежит, 14 МБ, `arm64-v8a`);
- `applicationId` и `namespace` = `dev.commy.app` (шаблон ставит имя проекта);
- ABI splits + universal APK;
- release `signingConfig` из `key.properties` или переменных окружения, с
  откатом на debug-подпись, когда их нет — на этот откат опирается CI;
- всё содержимое `AndroidManifest.xml`: разрешения, `VpnService`, deep links;
- `buildFeatures { buildConfig = true }` и пин `ndkVersion` — см. выше.
