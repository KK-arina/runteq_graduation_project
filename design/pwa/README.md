# design/pwa（ホーム画面アイコンとマニフェストの説明）

<br>

このフォルダには、ホーム画面に追加したときのアイコンの**原本（SVG）**を置いています。<br>
PNG は `bash bin/generate_pwa_icons` で `public/pwa/` に書き出します。

<br>

## ファイルの対応表

<br>

| 原本（SVG） | 書き出す PNG | 使う場所 |
|:--|:--|:--|
| `icon-any.svg`（角丸） | `public/pwa/icon-192-v1.png`・`icon-512-v1.png` | マニフェストの `purpose: any`（Chrome / Edge / Android） |
| `icon-any.svg`（角丸） | `public/pwa/favicon-32-v1.png` | ブラウザのタブ（`<link rel="icon">`） |
| `icon-maskable.svg`（全面塗り・中央に縮小） | `public/pwa/icon-maskable-512-v1.png` | マニフェストの `purpose: maskable`（Android の丸・角丸の切り抜き） |
| `icon-full.svg`（全面塗り） | `public/pwa/apple-touch-icon-v1.png`（180px） | iPhone / iPad（`<link rel="apple-touch-icon">`） |
| `icon-full.svg`（全面塗り） | `public/apple-touch-icon.png`・`apple-touch-icon-precomposed.png` | `<link>` を見ずに直接取りに来るアクセス用（同じ画像のコピー） |

<br>

## マニフェスト（`public/pwa/manifest-v1.webmanifest`）の各項目

<br>

JSON の形式ではファイル内にコメントを書けないため、ここで説明します。<br>

| 項目 | 値 | 意味 |
|:--|:--|:--|
| `id` | `/` | アプリを見分ける ID。`start_url` を将来変えても「同じアプリ」として扱われるよう固定する |
| `name` / `short_name` | `HabitFlow` | インストール画面とホーム画面のアイコンの下に出る名前 |
| `description` | 説明文 | インストール画面に出る説明（layout の meta description と同じ内容） |
| `lang` / `dir` | `ja` / `ltr` | 日本語・左から右に読む |
| `start_url` | `/dashboard` | アイコンから開いたときの最初のページ。未ログインなら `require_login` が `/login?redirect_to=%2Fdashboard` に移動させ、ログイン後にダッシュボードへ戻る |
| `scope` | `/` | アプリとして扱う範囲。ログイン画面・OmniAuth のコールバック（`/auth/...`）も含めるため、サイト全体にする |
| `display` | `standalone` | アドレスバーのない、アプリのような画面で開く |
| `background_color` | `#f9fafb` | Android の起動画面の背景色（body の `bg-gray-50` と同じ色） |
| `theme_color` | `#2563eb` | ステータスバーやタイトルバーの色（テーマ色の青） |
| `icons` | 3つ | 192px・512px（any）と 512px（maskable）。Chrome のインストール条件で 192px と 512px が必要 |

<br>

## ファイル名に `-v1` を付けている理由

<br>

`config/environments/production.rb` で、`public/` のファイルには<br>
`Cache-Control: public, max-age=31536000, immutable`（1年間キャッシュ）が付きます。<br>
同じファイル名のまま中身を変えると、ブラウザが古いアイコンを表示し続けるため、<br>
変更するときは `-v2` のように**ファイル名ごと変えます**（`bin/generate_pwa_icons` の冒頭を参照）。