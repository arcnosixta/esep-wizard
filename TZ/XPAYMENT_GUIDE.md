# XPayment интеграция в esep-web

## Общая карта
- Flutter-экран оплаты: `lib/screens/payment_screen.dart`
- Служба платежей: `lib/services/payment_service.dart`
- Новые заглушки XPayment:
  - `lib/services/xpayment_service.dart`
  - `lib/screens/xpayment_screen.dart`
- Бэкенд Cloudflare Pages Functions:
  - `functions/api/kaspi.js`  — Kaspi Pay (демо, уже работает)
  - `functions/api/xpayment.js` — XPayment (заглушка)
- SQL для Supabase:
  - `supabase_payments.sql` — текущая схема платежей
  - `supabase_xpayment.sql` — заглушка таблицы/миграции XPayment

## Что уже работает (не трогать)
- Банковский перевод + ручное подтверждение менеджером.
- Kaspi Pay (онлайн) через edge-функцию `functions/api/kaspi.js`:
  - `POST /api/kaspi/create` — создаёт платёж `provider='kaspi'`, возвращает `checkout_url`.
  - `GET /api/kaspi/checkout` — демо-страница оплаты.
  - `POST /api/kaspi/webhook` — подтверждает платёж и переводит заявку в `paid`.
- Заглушки XPayment уже лежат в репозитории и **не ломают текущую оплату**.

## Точки входа для второй части (XPayment)
1. `lib/services/xpayment_service.dart` — заменить `UnimplementedError` на реальные вызовы SDK/серверных эндпоинтов XPayment.
2. `lib/screens/xpayment_screen.dart` — встроить настоящий виджет оплаты XPayment.
3. `functions/api/xpayment.js` — реализовать:
   - `POST /api/xpayment/create` — создать сессию в XPayment, сохранить в Supabase, вернуть `checkout_url`.
   - `POST /api/xpayment/webhook` — принять статус от XPayment, подтвердить платёж, перевести заявку в `paid`.
4. `supabase_xpayment.sql` — актуализировать схему под API XPayment при необходимости.

## Как подключить кнопку XPayment в текущий PaymentScreen
В `lib/screens/payment_screen.dart` внутри `_methodsSection` добавь 4-й способ оплаты:

```dart
_paymentRow(
  context: context,
  index: 3,
  icon: Icons.payment_rounded,
  label: 'XPayment',
  subtitle: 'Онлайн-оплата через XPayment',
  color: c.accent,
),
Container(height: 1, margin: const EdgeInsets.only(left: 56), color: c.divider),
```

И в ветку выбора блока:

```dart
if (_selectedMethod == 3) ...[
  const SizedBox(height: 14),
  // TODO: встроить реальный блок XPayment
]
```

Открывать экран:

```dart
AppNavigator.push(context, const XPaymentScreen());
```

## Контракт данных
- Цена оценки: `PaymentService.appraisalPrice` (= 15000 ₸).
- Методы: `bank`, `kaspi`, `kaspi_online`, `xpayment`.
- Статусы платежей: `pending`, `paid`, `failed`, `cancelled`.
- При успешном платеже:
  - обновить `payments.status = 'paid'`,
  - обновить `applications.status = 'paid'`,
  - если есть отчёт — `reports.is_paid = true`, `reports.status = 'paid'`.

## Безопасность
- Все серверные эндпоинты `/api/xpayment/*` проверяют Bearer-токен Supabase JWT.
- Подпись вебхука XPayment проверяется на секрете (HMAC-SHA256).
- Никакие секреты/ключи не коммитить в репозиторий — только env vars в Cloudflare Pages Settings.

## Миграция БД
Перед запуском нового кода выполнить в Supabase SQL Editor:

```sql
-- payments + pending_payment (уже есть в supabase_payments.sql)
\i supabase_payments.sql

-- XPayment заглушка (если нужна)
\i supabase_xpayment.sql
```

## Где искать контекст
- Текущий `PaymentService`: `lib/services/payment_service.dart`
- Пример работающего Kaspi-интеграции: `functions/api/kaspi.js`
- Использование `PaymentScreen`: `lib/screens/home_screen.dart`, `lib/screens/case_detail_screen.dart`
