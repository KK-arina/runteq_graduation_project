// app/javascript/controllers/install_banner_controller.js
//
// =============================================================================
// InstallBannerController: ダッシュボードの「ホーム画面に追加」バナーを ✕ で閉じる
// =============================================================================
//
// 【役割】
//   ✕ を押したら「閉じた」ことをブラウザの localStorage に記録し、次からは表示しない。
//
// 【サーバーに何も送らない理由】
//   閉じた状態を DB に保存すると、そのたびに Neon へのアクセスが増える。
//   この案内は「端末ごとに一度閉じれば十分」なので、ブラウザの中だけで完結させる。
//   （dismissible_controller.js はサーバーへ保存する作りのため、ここでは使わない）
//
// 【ホーム画面から開いているときに隠す処理】
//   このコントローラーではなく、外側の pwa-guide コントローラー（browserOnly）が担当する。
//
// 【JavaScript が動かない場合】
//   バナーは最初から hidden（非表示）で出力しているので、表示されないだけで、ほかに影響はない。
// =============================================================================
import { Controller } from "@hotwired/stimulus"

// localStorage に保存するときの名前（キー）
//   末尾の :v1 … 将来、案内の内容を大きく変えてもう一度見せたいときに、:v2 に変えれば全員に再表示できる
const STORAGE_KEY = "habitflow:install-banner-dismissed:v1"

// localStorage が使えない環境（プライベートブラウズや一部のアプリ内ブラウザ）でも、
// 同じページを開いている間（Turbo の画面移動の間）は閉じたままにするための目印
let dismissedInThisPage = false

// 閉じたことがあるかを読み取る
//   try / catch … localStorage が使えない環境では例外が出るため、そのときは「閉じていない」とみなす
const readDismissed = () => {
  if (dismissedInThisPage) return true

  try {
    return window.localStorage.getItem(STORAGE_KEY) === "1"
  } catch (_error) {
    return false
  }
}

// 閉じたことを記録する
const writeDismissed = () => {
  dismissedInThisPage = true

  try {
    window.localStorage.setItem(STORAGE_KEY, "1")
  } catch (_error) {
    // 保存できなくても、このページを開いている間は閉じたままになるので問題ない
  }
}

export default class extends Controller {
  // Stimulus がこの要素を見つけたときに呼ばれる（Turbo で画面を移動して戻ってきたときも呼ばれる）
  //   閉じたことがなければ表示し、閉じたことがあれば非表示のままにする
  connect() {
    this.element.hidden = readDismissed()
  }

  // ✕ ボタンから呼ばれる（data-action="install-banner#dismiss"）
  dismiss() {
    this.element.hidden = true
    writeDismissed()
  }
}
