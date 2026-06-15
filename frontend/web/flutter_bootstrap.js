{{flutter_js}}
{{flutter_build_config}}

// 既存のサービスワーカーをすべて登録解除してキャッシュを全削除する。
// SW がデプロイ後の古いコードを提供し続ける問題を防ぐ。
(async function () {
  try {
    if ('serviceWorker' in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map(r => r.unregister()));
    }
    if ('caches' in window) {
      const keys = await caches.keys();
      await Promise.all(keys.map(k => caches.delete(k)));
    }
  } catch (_) {}
})();

// SW なしで Flutter をロード（新規 SW は登録しない）
_flutter.loader.load();
