# 15 · Хэндофф следующему агенту

> Написано 2026-08-04 в конце длинной сессии. Здесь состояние на момент передачи,
> что делать дальше и на чём здесь уже спотыкались. Читай целиком — половина
> документа это грабли, каждая из которых стоила от получаса до часа.
>
> План работ — [14-execution-plan.md](14-execution-plan.md).
> Контракт проекта — [../CLAUDE.md](../CLAUDE.md).

---

## 1. Где мы

**Готово и проверено на живом тулчейне.** Не «написано», а прогнано.

| Пакет | analyze | тесты |
|---|---|---|
| `commy_domain` | `No issues found!` | 45 |
| `commy_config` | `No issues found!` | 256 |
| `commy_core` | `No issues found!` | 146 |
| `commy_data` | `No issues found!` | 132 |
| `commy_ui` | `No issues found!` | 145 |
| | | **724** |

```
melos run analyze --no-select   →  SUCCESS
melos run test --no-select      →  SUCCESS
```

- **`libbox.aar` собран** — 14 МБ, `jni/arm64-v8a/libbox.so`, minSdk 24, лежит в
  `apps/commy/android/app/libs/`. Пересобирается `scripts/build_core.sh android`.
- **Android-туннель написан** — 22 файла Kotlin, включая `CommyVpnService`,
  `CommyPlatformInterface`, `CommandClientAdapter`, `CoreEventBridge`.
- **Gradle-каркас** — `settings/build/app/build.gradle.kts`, манифест, ресурсы,
  ProGuard, иконки во всех плотностях.
- **Обвязка репозитория** — LICENSE (GPL-3.0), README, CHANGELOG, CoC,
  4 воркфлоу CI, CodeQL, dependabot, 4 issue-формы, PR-шаблон.

**Не готово.**

- ❌ **APK ни разу не собрался.** Подробности в разделе 4 — это среда, не проект.
- ❌ **Приложения нет.** В `apps/commy/lib/` один файл `main.dart`, и это
  **заглушка**, написанная чтобы проверить сборочную цепочку. Экранов,
  роутинга, провайдеров, локализации — нет вообще. Это самая большая
  оставшаяся работа.
- ❌ **Коммитов нет.** 577 файлов не в индексе. `git init` сделан, remote
  `https://github.com/Makhkets/commy.git` прописан, репозиторий на GitHub
  переименован из `Comlent` и оформлен.
- ❌ **Живой туннель не проверен.** Нужна настоящая подписка от владельца.

---

## 2. Что делать дальше, по порядку

### Шаг 1 — закоммитить и запушить. Сделай это первым.

577 файлов и **ноль коммитов**. Всё, что описано выше, живёт только на диске
этой машины. Любой сбой сейчас стоит всей ночи работы.

```bash
git add -A
git commit -m "feat: monorepo foundation, sing-box core, Android tunnel"
git push -u origin main
```

Это же запустит CI, который соберёт APK на Linux-раннере — см. шаг 2.

### Шаг 2 — получить APK из CI, а не из локальной сборки

`.github/workflows/ci.yml`, задача `android`, собирает всё с нуля: `libbox.aar`
через `gomobile bind`, потом debug APK, и **проверяет, что внутри артефакта
реально лежит `lib/arm64-v8a/libbox.so`**. Ни одна из трёх Windows-проблем из
раздела 4 на Linux не существует.

Локальную сборку добивать стоит только ради быстрого цикла отладки. Ради самого
артефакта — не стоит.

### Шаг 3 — написать приложение

Самая большая работа. Всё, на что оно опирается, готово и покрыто тестами.

Читай перед началом:
- [05-ux-flows.md](05-ux-flows.md) — экраны, состояния, сценарии;
- [design-refs/](design-refs/) — **PNG-рендеры всех 10 утверждённых экранов**
  плюс README с таблицей «файл → node ID → что проверяем». Это источник истины
  для композиции;
- барели пакетов: `commy_domain.dart`, `commy_ui.dart`, `commy_core.dart`.

Что именно строить:
1. Composition root, `ProviderScope` с переопределяемыми инфраструктурными
   провайдерами, `MaterialApp.router`, обе темы из `commy_ui`.
2. `go_router`. **Нижнего меню на мобайле нет** — один корневой экран, настройки
   за шестерёнкой, импорт за плюсом в bottom sheet.
3. Экраны, каждый с четырьмя обязательными состояниями (скелетон / пусто с
   действием / ошибка с причиной, действием и путём к логам / контент).
4. `slang`: `assets/i18n/strings_ru.i18n.json` и `strings_en.i18n.json`.
   Каждая строка, включая тексты всех `CommyFailure` и метки их действий.
5. Сквозной поток: импорт → сохранение → выбор узла → `ConnectUseCase` →
   `SingBoxConfigBuilder` → `CoreClient.start` → потоки статуса и трафика.
   Смена узла — через `select()`, **не** через перезапуск.

Riverpod **без** генератора, freezed нет — см. [ADR-0006](adr/0006-codegen-and-native-layout.md).

### Шаг 4 — свести экраны с макетами

По агенту на экран, у каждого свой PNG перед глазами. Композицию проверяет
картинка, значения берутся из токенов `commy_ui` — пипеткой по скриншоту не
подбирать: рендер идёт в 390×844 и его пиксели не авторитетны для величин.

### Шаг 5 — живой туннель

**Требует подписки от владельца.** Синтетика здесь ничего не доказывает.
Проверять: импорт подписки и разбор `subscription-userinfo`; подключение →
`checking` → `connected` и смена IP; переживание Wi-Fi ↔ мобильная сеть без
переподключения; переживание Doze; понятная ошибка при отказе в системном
диалоге VPN.

---

## 3. Что здесь устроено не так, как ты ожидаешь

Прочитай, прежде чем «чинить».

**Кодогенерации почти нет.** Только `drift` и `slang`. Вместо freezed —
нативные sealed-классы Dart 3, Riverpod без генератора.
[ADR-0006](adr/0006-codegen-and-native-layout.md).

**База не шифруется целиком.** `sqlcipher_flutter_libs` и `sqlite3_flutter_libs`
оба помечены EOL. Креды, ссылки подписок и сгенерированный конфиг живут в
Keystore через `flutter_secure_storage`, в SQLite только метаданные.
[ADR-0007](adr/0007-database-encryption.md). Это **не** ослабление R2 — там же
разбор почему.

**Kotlin лежит в `apps/commy/android/`, а не в `native/android/`**, вопреки карте
репозитория в CLAUDE.md §3. Gradle Flutter'а ждёт его там. ADR-0006.

**Набор build-тегов sing-box короче апстримного** — 7 вместо 20. Выброшены
`with_naive_outbound` и `with_tailscale`. Проверено по `include/registry.go`,
что ни один заявленный протокол не потерялся.
[13-libbox-reference.md](13-libbox-reference.md).

**`LogLineView`, а не `LogLine`** в `commy_ui`: имя `LogLine` уже занято
сущностью домена, и приложение, импортирующее оба пакета, споткнулось бы на
неоднозначном импорте.

---

## 4. Грабли. Каждая проверена на собственной шкуре

### Сборка ядра

| Симптом | Причина |
|---|---|
| `gomobile bind` печатает справку и выходит с кодом 0, файла нет | Апстримный `golang.org/x/mobile` **не тот gomobile**. Нужен `github.com/sagernet/gomobile@v0.1.12` |
| `"github.com/sagernet/gomobile/bind" is not found` | `gobind` резолвит пакет из **биндимого** модуля. Нужен blank-импорт под тегом `tools` — `core/internal/tools/gomobile.go` |
| `missing go.sum entry for github.com/go-chi/render` | `go mod tidy` **не принимает `-tags`**. Только `GOFLAGS="-tags=..." go mod tidy` |
| `exec: "javac": not found` — **после** компиляции всего ядра | Git Bash отдаёт Windows-программе PATH в Unix-виде. `need_javac` в `scripts/build_core.sh` резолвит через `cygpath` |

### Gradle на Windows

Все четыре воспроизводились, все четыре закрыты в `gradle.properties` с
объяснением прямо в файле. **Не включай их обратно «для скорости».**

| Симптом | Причина |
|---|---|
| `Timeout waiting to lock build logic queue. Owner PID: N` | Кто-то ещё гоняет Gradle в этой же директории. Если **PID меняется** между попытками — это живой процесс, жди. Если постоянный — мусор, чисти `.gradle` |
| `Could not get file mode for R.jar` на 15-й минуте | `org.gradle.caching=true`. Упаковка результатов читает POSIX-права, которых в NTFS нет |
| `Could not delete ...\caches-jvm` | `kotlin.incremental=true` и/или `org.gradle.parallel=true`. Оба выключены |
| `NDK not configured. Preferred NDK version is '28.2.13676358'` | Каждый Flutter-плагин — свой подпроект со своим `ndkVersion`. Пин только в `:app` **не помогает**. Пин навязан всем подпроектам в корневом `build.gradle.kts`, **через `afterEvaluate`** — `plugins.withId` срабатывает раньше, чем подпроект выставит своё значение, и пин перезаписывается |
| `NDK ... did not have a source.properties file` | Неудачная докачка NDK оставила пустую папку. Удалить `$ANDROID_HOME/ndk/<версия>` |

### melos на Windows

| Симптом | Причина |
|---|---|
| `FormatException: Unexpected extension byte` | Запущен из **Git Bash**. Запускать из PowerShell |
| `StdinException: Error getting terminal echo mode` | Нужен `--no-select` для любого скрипта с `packageFilters` |
| `ERROR: "melos" не является внутренней командой` | Скрипты зовут `melos exec`. Нужна глобальная активация **той же версии**: `dart pub global activate melos 6.3.3` |

### Работа агентами

**За сессию умерло около половины запущенных агентов** — часть от
`API Error: Response stalled mid-stream`, часть от лимита использования.

- «Воркфлоу выполняется» **не означает** «его агенты живы». Смотри на рост
  файлов и время модификации транскриптов в
  `.claude/.../subagents/workflows/<runId>/agent-*.jsonl`.
- Работа при этом почти не терялась: агенты пишут файлы по ходу. **Трижды**
  оказывалось, что пакет фактически готов, а потерян только финальный отчёт.
  Прежде чем перезапускать — проверь, что на диске.
- Владельца транскрипта достаёшь grep'ом первой строки `YOU OWN:`.
- Возвращаемое значение в `journal.jsonl` лежит под ключом **`result`**, не
  `value`.
- Не запускай сборку в директории, которой владеет живой агент.

---

## 5. Тулчейн

Машина пришла пустой. Всё поставлено zip-ами в `C:\dev`, без прав администратора.

| Что | Где |
|---|---|
| Flutter 3.44.8 (Dart 3.12.2) | `C:\dev\flutter` |
| JDK 17.0.20 Temurin | `C:\dev\jdk17` |
| Android SDK, platform 35/36, build-tools 36 | `C:\dev\android-sdk` |
| NDK **28.0.13004108** | `C:\dev\android-sdk\ndk\` |
| melos 6.3.3 | `%LOCALAPPDATA%\Pub\Cache\bin` |
| gomobile (форк SagerNet) | `%USERPROFILE%\go\bin` |

Под bash JDK в PATH добавлять как `/c/dev/jdk17/bin` — Windows-путь для
дочерних процессов невидим.

---

## 6. Чем проверять, что ничего не разъехалось

Обе проверки уже в CI. Гоняй их после любой правки Kotlin или `commy_core`.

```bash
# контракт каналов Dart <-> Kotlin
python scripts/check_wire_contract.py

# наш PlatformInterface против того, что реально объявляет AAR
unzip -o -q apps/commy/android/app/libs/libbox.aar classes.jar
javap -cp classes.jar io.nekohasekai.libbox.PlatformInterface \
  | grep -oE '[a-zA-Z]+\(' | tr -d '(' | sort > /tmp/required.txt
grep -oE 'override fun [a-zA-Z]+' \
  apps/commy/android/app/src/main/kotlin/dev/commy/app/tunnel/CommyPlatformInterface.kt \
  | sed 's/override fun //' | sort > /tmp/implemented.txt
diff /tmp/required.txt /tmp/implemented.txt
```

Обе на момент передачи сходятся: 15 методов из 15, и 5 каналов + 7 методов +
5 состояний + 8 кодов ошибок + 27 JSON-ключей.

---

## 7. Что нужно от владельца

1. **Подписка** (remnawave или любая другая) — без неё «APK собирается» и «VPN
   работает» остаются разными утверждениями, и выдавать одно за другое нельзя.
2. **Apple Developer Program** — если нужен iOS. Пока действует escape hatch из
   [07-roadmap.md](07-roadmap.md): 1.0 выходит Android-only.
3. **Переименование папки** `Desktop\Comlent` → `Desktop\Commy` и файла в Figma.
   Внутри всё уже `Commy`; папку не трогали, чтобы не уронить сессию.

---

## 8. Главное, если читать нечего кроме одного абзаца

Фундамент готов и проверен: пять пакетов, 724 теста, чистый анализ, собранное
ядро sing-box, написанный Android-туннель, сверенный с реальным API по машинной
проверке. **Не хватает приложения** — в `apps/commy/lib` заглушка, — и **ничего
не закоммичено**. Коммить первым делом, APK бери из CI, потом пиши экраны по
PNG в `docs/design-refs/`.
