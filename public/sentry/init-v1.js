// public/sentry/init-v1.js
//
// 【このファイルの役割】
//   Sentry Browser SDK（/sentry/bundle.min.js）を初期化する。
//   レイアウト（app/views/layouts/application.html.erb）で、bundle.min.js の直後に defer で読み込まれる。
//   defer のスクリプトは HTML に書かれた順に実行されるので、この時点では window.Sentry が用意されている。
//   （以前はレイアウトに直接書いていたが、インラインの script には defer が効かないため、別ファイルに分けた）
//
// 【設定値の受け取り方】
//   DSN とリリース（コミット SHA）は、レイアウトの <meta name="sentry-dsn"> と
//   <meta name="sentry-release"> から読む。このファイルは public/ の静的ファイルで、
//   ERB を使って値を埋め込めないため。
//
// 【ファイル名の -v1】
//   public/ のファイルは本番で 1 年間キャッシュされる。中身を変えるときは
//   init-v2.js のように新しい名前で作り、レイアウトの読み込み先も変える。

(function () {
  // SDK 本体の読み込みに失敗していたら何もしない（エラーを出して画面を壊さないため）
  if (!window.Sentry) return;

  // 指定した名前の meta タグの content を読む。見つからなければ空文字を返す
  function readMeta(name) {
    var element = document.querySelector('meta[name="' + name + '"]');
    return element ? element.content : "";
  }

  var dsn = readMeta("sentry-dsn");
  // DSN が無ければ送信先が分からないので、初期化しない
  if (!dsn) return;

  window.Sentry.init({
    // 送信先 DSN（バックエンドと同じプロジェクト）
    dsn: dsn,
    // Render が自動で設定するコミット SHA。「どのデプロイの JS で起きたか」をバックエンドと突き合わせる
    // 空文字のときは undefined にして、リリース無しとして扱わせる
    release: readMeta("sentry-release") || undefined,
    // 環境名を production として明示（Sentry 画面のフィルタ用）
    environment: "production"
  });
})();