// Cloudflare Pages Function — XPayment (xpayment.kz) — Kaspi Pay через API.
//
// Эндпоинты:
//
//   POST /api/xpayment/create   — клиент из приложения: создаёт платёж
//                                 (status=pending, provider='xpayment'),
//                                 запрашивает платёжную ссылку у XPayment и
//                                 возвращает checkout_url.
//   POST /api/xpayment/status   — синхронизация: спрашивает статус платежей у
//                                 XPayment (GET /v1/payments/{ext_tran_id}) и
//                                 при COMPLETED подтверждает платёж.
//   GET  /api/xpayment/checkout — демо-страница оплаты (тестовый режим,
//                                 когда XPAYMENT_API_KEY ещё не задан).
//   POST /api/xpayment/webhook  — события XPayment (payment.completed и др.);
//                                 подпись X-xPayment-Signature = HMAC-SHA256
//                                 от «сырого» тела, ключ — WEBHOOK_SECRET.
//
// Env-переменные:
//   SUPABASE_URL, SUPABASE_ANON_KEY   — JWT-авторизация (как в kaspi.js)
//   SUPABASE_SERVICE_ROLE_KEY         — серверная запись (confirmPayment)
//   XPAYMENT_API_KEY                  — ключ устройства xpayment (xdev_...)
//   XPAYMENT_API_URL                  — базовый URL API XPayment
//                                       (по умолчанию https://api.xpayment.kz)
//   XPAYMENT_WEBHOOK_SECRET           — секрет вебхука для HMAC-SHA256
//
// БЕЗОПАСНОСТЬ: если XPAYMENT_WEBHOOK_SECRET задан — вебхук принимает только
// запросы с валидной подписью. Если не задан — работает только тестовый режим
// (body.test === true с демо-страницы), остальные запросы получают 503.

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-xPayment-Signature',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}
function jsonError(message, status) {
  return json({ error: message }, status);
}

async function authorizeRequest(request, env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
  const auth = request.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return { status: 401, message: 'Unauthorized: missing Bearer token' };
  const token = auth.slice(7).trim();
  if (!token) return { status: 401, message: 'Unauthorized: empty token' };
  try {
    const resp = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${token}`, apikey: env.SUPABASE_ANON_KEY },
    });
    if (!resp.ok) return { status: 401, message: 'Unauthorized: invalid token' };
  } catch (_) {
    return { status: 503, message: 'Auth service unavailable' };
  }
  return null;
}

function sbHeaders(env) {
  return {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    'Content-Type': 'application/json',
  };
}

async function confirmPaymentServerSide(env, paymentId) {
  const payRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/payments?id=eq.${paymentId}&status=neq.paid&select=application_id`,
    {
      method: 'PATCH',
      headers: { ...sbHeaders(env), Prefer: 'return=representation' },
      body: JSON.stringify({
        status: 'paid',
        confirmed_at: new Date().toISOString(),
        confirmed_by: 'xpayment_webhook',
      }),
    },
  );
  if (!payRes.ok) return { ok: false, error: 'payments update failed' };
  const rows = await payRes.json();
  const appId = rows?.[0]?.application_id;
  if (!appId) return { ok: true };

  await fetch(`${env.SUPABASE_URL}/rest/v1/applications?id=eq.${appId}`, {
    method: 'PATCH',
    headers: { ...sbHeaders(env), Prefer: 'return=minimal' },
    body: JSON.stringify({ status: 'paid' }),
  });

  const repRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/reports?application_id=eq.${appId}&select=id`,
    { headers: sbHeaders(env) },
  );
  if (repRes.ok) {
    const reps = await repRes.json();
    for (const r of reps) {
      await fetch(`${env.SUPABASE_URL}/rest/v1/reports?id=eq.${r.id}`, {
        method: 'PATCH',
        headers: { ...sbHeaders(env), Prefer: 'return=minimal' },
        body: JSON.stringify({ is_paid: true, status: 'paid' }),
      });
    }
  }
  return { ok: true };
}

async function failPaymentServerSide(env, paymentId, status) {
  await fetch(`${env.SUPABASE_URL}/rest/v1/payments?id=eq.${paymentId}&status=eq.pending`, {
    method: 'PATCH',
    headers: { ...sbHeaders(env), Prefer: 'return=minimal' },
    body: JSON.stringify({ status }),
  });
  return { ok: true };
}

async function xpaymentApiUrl(env) {
  return (env.XPAYMENT_API_URL || 'https://api.xpayment.kz').replace(/\/+$/, '');
}

// Платёжная ссылка: POST /v1/payments/link → { payment_link, ext_tran_id, ... }
async function createXpaymentLink(env, amount) {
  const resp = await fetch(`${await xpaymentApiUrl(env)}/v1/payments/link`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.XPAYMENT_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ amount: Number(amount) }),
  });
  const data = await resp.json().catch(() => null);
  if (!resp.ok || !data?.payment_link) {
    return { error: data?.error || data?.message || `HTTP ${resp.status}` };
  }
  return { link: data.payment_link, extTranId: data.ext_tran_id || null };
}

// Статус платежа: GET /v1/payments/{ext_tran_id} → { status: 'COMPLETED'|... }
async function getXpaymentStatus(env, extTranId) {
  const resp = await fetch(`${await xpaymentApiUrl(env)}/v1/payments/${encodeURIComponent(extTranId)}`, {
    headers: { Authorization: `Bearer ${env.XPAYMENT_API_KEY}` },
  });
  const data = await resp.json().catch(() => null);
  if (!resp.ok || !data) return null;
  return String(data.status || '').toUpperCase();
}

// Подпись вебхука: hex(HMAC-SHA256(secret, raw_body)), сравнение constant-time.
async function verifyWebhookSignature(secret, rawBody, signature) {
  if (!secret || !signature) return false;
  try {
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const mac = await crypto.subtle.sign('HMAC', key, rawBody);
    const expected = [...new Uint8Array(mac)]
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    const a = new TextEncoder().encode(expected);
    const b = new TextEncoder().encode(signature.trim().toLowerCase());
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff === 0;
  } catch (_) {
    return false;
  }
}

// Найти наш платёж: по merchant_order_id (= payments.id) или по
// provider_tx_id (= ext_tran_id / payment_id XPayment).
async function findOurPayment(env, body) {
  const candidates = [];
  if (body.merchant_order_id) candidates.push(`id=eq.${encodeURIComponent(body.merchant_order_id)}`);
  if (body.payment_id) {
    candidates.push(`provider_tx_id=eq.${encodeURIComponent(body.payment_id)}`);
  }
  for (const filter of candidates) {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/payments?${filter}&select=id,status,application_id&limit=1`, {
      headers: sbHeaders(env),
    });
    if (res.ok) {
      const rows = await res.json();
      if (rows?.length) return rows[0];
    }
  }
  return null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const { pathname } = url;
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: JSON_HEADERS });

    // ── POST /api/xpayment/create ──────────────────────────────────────
    if (pathname === '/api/xpayment/create' && request.method === 'POST') {
      const authErr = await authorizeRequest(request, env);
      if (authErr) return jsonError(authErr.message, authErr.status);

      let body;
      try { body = await request.json(); } catch (_) { return jsonError('Invalid JSON', 400); }
      const { application_id: appId, amount } = body;
      if (!appId || !amount) return jsonError('application_id and amount required', 400);

      const insRes = await fetch(`${env.SUPABASE_URL}/rest/v1/payments`, {
        method: 'POST',
        headers: { ...sbHeaders(env), Prefer: 'return=representation' },
        body: JSON.stringify({
          application_id: appId,
          amount,
          method: 'xpayment',
          status: 'pending',
          provider: 'xpayment',
        }),
      });
      if (!insRes.ok) return jsonError('Failed to create payment', 502);
      const created = (await insRes.json())?.[0];

      await fetch(`${env.SUPABASE_URL}/rest/v1/applications?id=eq.${appId}`, {
        method: 'PATCH',
        headers: { ...sbHeaders(env), Prefer: 'return=minimal' },
        body: JSON.stringify({ status: 'pending_payment' }),
      });

      // Реальная платёжная ссылка XPayment (Kaspi откроется на телефоне).
      if (env.XPAYMENT_API_KEY) {
        const link = await createXpaymentLink(env, amount);
        if (link.error) {
          await failPaymentServerSide(env, created.id, 'failed');
          return jsonError(`XPayment: ${link.error}`, 502);
        }
        if (link.extTranId) {
          await fetch(`${env.SUPABASE_URL}/rest/v1/payments?id=eq.${created.id}`, {
            method: 'PATCH',
            headers: { ...sbHeaders(env), Prefer: 'return=minimal' },
            body: JSON.stringify({ provider_tx_id: link.extTranId }),
          });
        }
        return json({
          payment_id: created.id,
          checkout_url: link.link,
          test_mode: false,
        });
      }

      // Тестовый режим: демо-страница, как у Kaspi-заглушки.
      const origin = url.origin;
      return json({
        payment_id: created.id,
        checkout_url: `${origin}/api/xpayment/checkout?payment_id=${created.id}&amount=${amount}`,
        test_mode: true,
      });
    }

    // ── POST /api/xpayment/status (поллинг из приложения) ──────────────
    if (pathname === '/api/xpayment/status' && request.method === 'POST') {
      const authErr = await authorizeRequest(request, env);
      if (authErr) return jsonError(authErr.message, authErr.status);

      let body;
      try { body = await request.json(); } catch (_) { return jsonError('Invalid JSON', 400); }
      const appId = body.application_id;
      if (!appId) return jsonError('application_id required', 400);
      if (!env.XPAYMENT_API_KEY) return json({ ok: true, checked: 0, test_mode: true });

      const pendRes = await fetch(
        `${env.SUPABASE_URL}/rest/v1/payments?application_id=eq.${encodeURIComponent(appId)}&provider=eq.xpayment&status=eq.pending&select=id,provider_tx_id`,
        { headers: sbHeaders(env) },
      );
      if (!pendRes.ok) return jsonError('Failed to load payments', 502);
      const pending = (await pendRes.json()) || [];

      let confirmed = 0;
      for (const p of pending) {
        if (!p.provider_tx_id) continue;
        const status = await getXpaymentStatus(env, p.provider_tx_id);
        if (status === 'COMPLETED') {
          const res = await confirmPaymentServerSide(env, p.id);
          if (res.ok) confirmed += 1;
        } else if (status === 'FAILED') {
          await failPaymentServerSide(env, p.id, 'failed');
        } else if (status === 'CANCELLED') {
          await failPaymentServerSide(env, p.id, 'cancelled');
        }
      }
      return json({ ok: true, checked: pending.length, confirmed });
    }

    // ── GET /api/xpayment/checkout (демо-страница) ─────────────────────
    if (pathname === '/api/xpayment/checkout' && request.method === 'GET') {
      const paymentId = url.searchParams.get('payment_id') || '';
      const amount = url.searchParams.get('amount') || '0';
      const html = `<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>XPayment — ESEP</title><style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:#f6f6f6;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.card{background:#fff;border-radius:16px;padding:32px;max-width:400px;width:90%;box-shadow:0 4px 24px rgba(0,0,0,.08);text-align:center}
.logo{font-size:22px;font-weight:700;color:#1a1a1a;margin-bottom:4px}
.sub{color:#666;font-size:13px;margin-bottom:24px}
.amount{font-size:34px;font-weight:700;color:#1a1a1a;margin-bottom:24px}
.badge{display:inline-block;background:#fff4e5;color:#b45309;font-size:12px;padding:4px 10px;border-radius:99px;margin-bottom:16px}
.btn{background:#00b14f;color:#fff;border:none;border-radius:12px;padding:14px 0;width:100%;font-size:16px;font-weight:600;cursor:pointer}
.btn:disabled{opacity:.6;cursor:wait}
.status{margin-top:16px;font-size:14px;color:#16a34a;display:none}
.err{margin-top:16px;font-size:14px;color:#dc2626;display:none}
</style></head><body>
<div class="card">
  <div class="logo">ESEP</div>
  <div class="sub">Официальный отчёт об оценке · XPayment</div>
  <div class="badge">ТЕСТОВЫЙ РЕЖИМ — реальный XPayment подключается ключом XPAYMENT_API_KEY</div>
  <div class="amount">${Number(amount).toLocaleString('ru-RU')} ₸</div>
  <button class="btn" id="pay">Оплатить</button>
  <div class="status" id="status">✅ Платёж подтверждён! Можете закрыть вкладку.</div>
  <div class="err" id="err"></div>
</div>
<script>
const payBtn = document.getElementById('pay');
const statusEl = document.getElementById('status');
const errEl = document.getElementById('err');
payBtn.onclick = async () => {
  payBtn.disabled = true; payBtn.textContent = 'Обработка…';
  try {
    const r = await fetch('/api/xpayment/webhook', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({event: 'payment.completed', payment_id: ${JSON.stringify(paymentId)}, test: true}),
    });
    if (!r.ok) throw new Error((await r.json()).error || 'Ошибка');
    statusEl.style.display = 'block';
    payBtn.style.display = 'none';
  } catch (e) {
    errEl.textContent = 'Ошибка: ' + e.message;
    errEl.style.display = 'block';
    payBtn.disabled = false; payBtn.textContent = 'Оплатить';
  }
};
</script></body></html>`;
      return new Response(html, { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
    }

    // ── POST /api/xpayment/webhook ─────────────────────────────────────
    if (pathname === '/api/xpayment/webhook' && request.method === 'POST') {
      const rawBody = await request.arrayBuffer();
      let body;
      try { body = JSON.parse(new TextDecoder().decode(rawBody)); } catch (_) { return jsonError('Invalid JSON', 400); }

      const signature = request.headers.get('X-xPayment-Signature') || '';
      if (env.XPAYMENT_WEBHOOK_SECRET) {
        const valid = await verifyWebhookSignature(env.XPAYMENT_WEBHOOK_SECRET, rawBody, signature);
        if (!valid) return jsonError('Invalid signature', 401);
      } else if (body.test !== true) {
        return jsonError('Webhook not configured (XPAYMENT_WEBHOOK_SECRET missing)', 503);
      }

      const event = String(body.event || '');
      const our = await findOurPayment(env, body);
      if (!our) {
        // Неизвестный платёж — по рекомендациям xpayment отвечаем 200.
        return json({ ok: true, matched: false });
      }

      switch (event) {
        case 'payment.completed': {
          const res = await confirmPaymentServerSide(env, our.id);
          if (!res.ok) return jsonError(res.error, 502);
          return json({ ok: true, status: 'paid' });
        }
        case 'payment.failed':
          await failPaymentServerSide(env, our.id, 'failed');
          return json({ ok: true, status: 'failed' });
        case 'payment.cancelled':
        case 'payment.canceled':
          await failPaymentServerSide(env, our.id, 'cancelled');
          return json({ ok: true, status: 'cancelled' });
        case 'payment.expired':
          await failPaymentServerSide(env, our.id, 'cancelled');
          return json({ ok: true, status: 'cancelled' });
        default:
          // refund* и прочие события — подтверждаем получение без действий.
          return json({ ok: true });
      }
    }

    return jsonError('Not found', 404);
  },
};
