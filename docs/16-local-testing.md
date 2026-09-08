# 16 · Локальное тестирование против Remnawave

> Как поднять локальный туннель Commy с настоящей подпиской и проверить живой трафик.

---

## Зачем это нужно

Commy требует реальной подписки для:
1. Импорта подписки и парсинга `subscription-userinfo`
2. Получения списка узлов и их конфигов
3. Проверки туннеля в состояниях `checking` → `connected`
4. Измерения скорости и задержки
5. Тестирования переключений между сетями без разрыва соединения

**Без живой подписки** остаются проверенными только структура и базовая логика.
Критерии приёмки M1 требуют живого туннеля.

---

## Быстрый старт

### 1. Заполни `.env.local`

```bash
cp .env.example .env.local
```

Заполни реальные значения (используются из контакта владельца).
**Файл автоматически в `.gitignore` — не коммитится.**

### 2. Создай тестового пользователя

```bash
# Установи зависимость (один раз)
pip install python-dotenv httpx

# Создай пользователя с подпиской
python scripts/panel_test_setup.py --setup
```

Результат:
```
✅ User created: <user-id>
📋 Subscription URL:
https://panel.makhkets.ru/api/get_subscription?token=...
💾 Saved to: test_fixtures/test_subscription.private.json
```

### 3. Импортируй подписку в Commy

На экране импорта:
- **Способ:** ссылка
- **URL:** скопируй из предыдущего вывода или из файла `test_fixtures/test_subscription.private.json`
- Нажми **Импортировать**

Должно:
- Разобраться в `subscription-userinfo` (имя, траффик, срок)
- Показать список узлов
- Позволить выбрать узел и подключиться

### 4. Проверь подключение

На главном экране:
- Статус туннеля: `checking` → `connected`
- IP-адрес изменился (если включена E-1, проверка IP)
- Скорость подключения измеряется

---

## Очистка

Удалить тестового пользователя:

```bash
python scripts/panel_test_setup.py --cleanup --user-id <user-id-от-setup>
```

---

## Безопасность: как ключи хранятся

| Файл | Коммитится | Где | Доступ |
|---|---|---|---|
| `.env.local` | ❌ (в `.gitignore`) | На машине разработчика | Локально |
| `.env.example` | ✅ (публичный) | GitHub | Пример структуры, без значений |
| `test_fixtures/test_subscription.private.json` | ❌ (в `.gitignore`) | На машине разработчика | Локально |
| GitHub Secrets | Защищены GitHub | GitHub repo settings | CI/CD (для автотестов) |

**Если случайно закоммитилось:**
```bash
git rm --cached .env.local
git commit --amend
git push --force-with-lease
# Затем перегенерируй API ключ на панели
```

---

## Использование в CI (GitHub Actions)

Для автоматизированных тестов туннеля добавь GitHub Secrets:

1. Перейди в repo → Settings → Secrets and variables → Actions
2. Добавь три secrets:
   - `PANEL_URL`
   - `PANEL_API_KEY`
   - `TEST_USER_EMAIL`

3. В `.github/workflows/test.yml`:

```yaml
- name: Run integration tests
  env:
    PANEL_URL: ${{ secrets.PANEL_URL }}
    PANEL_API_KEY: ${{ secrets.PANEL_API_KEY }}
    TEST_USER_EMAIL: ${{ secrets.TEST_USER_EMAIL }}
  run: |
    python scripts/panel_test_setup.py --setup
    melos run test:integration
    python scripts/panel_test_setup.py --cleanup --user-id <captured-from-setup>
```

---

## Что проверять вручную

Сценарии, которые требуют живой подписки:

### Импорт подписки
- [ ] Ссылка парсится без ошибок
- [ ] `subscription-userinfo` показывает имя, лимит, срок
- [ ] Узлы загружаются
- [ ] Есть хотя бы один рабочий узел

### Подключение
- [ ] Статус: `idle` → `preparing` → `checking` → `connected`
- [ ] IP изменился (если узел работает)
- [ ] Задержка измеряется
- [ ] Скорость измеряется

### Стабильность
- [ ] Переключение Wi-Fi ↔ сотовая сеть без разрыва
- [ ] Приложение переживает lock/unlock экрана
- [ ] Приложение переживает Doze (Adaptive Battery)

### Разбор ошибок
- [ ] Неправильный пароль → ошибка парсинга
- [ ] Истекшая подписка → понятное сообщение
- [ ] Узел оффлайн → ошибка при попытке подключиться

---

## Известные проблемы

### Панель отдаёт заглушку вместо узлов

**Симптом:** `Subscription imported successfully` но узлы не загружаются или показана заглушка `vless://…@0.0.0.0:1`.

**Причина:** Проблема на стороне панели, не клиента. Этот блокер был на момент передачи (docs/15-handoff.md, раздел 0).

**Решение:** Проверить статус панели с владельцем.

### E-1, проверка IP, не работает

**Симптом:** Кнопка «Проверить IP» не отвечает.

**Причина:** Функция в списке задач (#1 в docs/15-handoff.md). Требует loopback mixed-инбаунда на панели.

**Решение:** До реализации проверяй вручную: вне туннеля и в туннеле ходи в IP-чекер и сравни.

---

## Как добавить новый тестовый сценарий

1. Добавь метод в `PanelAPI` класс в `scripts/panel_test_setup.py`
2. Вызови из `main()`
3. Сохрани результат в `test_fixtures/`
4. Добавь `.gitignore` правило если нужно

Пример:
```python
def get_nodes(self, user_id: str) -> list:
    """Fetch list of nodes available for user."""
    resp = self.client.get(f"/api/users/{user_id}/nodes")
    resp.raise_for_status()
    return resp.json()["nodes"]
```

---

## Контакты

Вопросы или проблемы с панелью — напиши владельцу (см. CLAUDE.md контракт проекта).
