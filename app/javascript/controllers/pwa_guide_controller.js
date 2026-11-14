// app/javascript/controllers/pwa_guide_controller.js
//
// =============================================================================
// PwaGuideController: 「ホーム画面に追加」の案内を、使っている端末に合わせて出し分ける
// =============================================================================
//
// 【使っている場所】
//   1. 設定ページの案内カード（app/views/settings/_pwa_install_guide.html.erb）
//      ・使っている端末の手順（iPhone / Android / PC / LINE などのアプリ内ブラウザ）を開いておく
//      ・ホーム画面から開いているときは「ホーム画面から開いています」を表示する
//      ・Chrome / Edge では「この端末にインストールする」ボタンを出す
//   2. ログイン画面の注意書き（app/views/shared/_pwa_login_notice.html.erb）
//      ・ホーム画面から開いているときだけ「ログインしたままにする」の案内を出す
//      ・iPhone のホーム画面アプリでは、Google / LINE ログインの注意も出す
//
// 【JavaScript が動かない場合】
//   案内の中身はすべてサーバー側の HTML に入っている（手順は閉じた状態で全部読める）。
//   このコントローラーは「見やすくする」だけなので、動かなくても案内は読める。
//
// 【サーバーに何も送らない理由】
//   端末の判定はブラウザの中だけで行い、結果を保存しない。
//   DB（Neon）へのアクセスを増やさないため。
// =============================================================================
import { Controller } from "@hotwired/stimulus"

// -----------------------------------------------------------------------------
// Chrome / Edge の「インストールできます」の合図（beforeinstallprompt）を受け取っておく
// -----------------------------------------------------------------------------
//
// 【なぜコントローラーの外（このファイルの一番上の階層）に書くのか】
//   beforeinstallprompt は、ページを最初に読み込んだときに1回だけ届く。
//   Turbo の画面移動ではページを読み込み直さないため、
//   ダッシュボードを開いてから設定ページへ移動すると、
//   設定ページのコントローラーが動き出す前に合図が届き終わっている。
//   controllers/index.js がアプリ起動時にこのファイルを読み込むので、
//   ここに書いておけば、どのページから入っても合図を取りこぼさない。
//
// 【event.preventDefault() を呼ばない理由】
//   preventDefault() を呼ぶと、Android の Chrome が自動で出す
//   「ホーム画面に追加」の案内（ミニ情報バー）が出なくなる。
//   利用者に気づいてもらう機会を減らさないため、ブラウザの案内はそのまま残し、
//   合図のオブジェクトだけを保存して、設定ページのボタンからも使えるようにする。
let deferredInstallPrompt = null

window.addEventListener("beforeinstallprompt", (event) => {
  deferredInstallPrompt = event
  // 表示中の案内カードに「ボタンを出してよい」と知らせる
  document.dispatchEvent(new CustomEvent("pwa-guide:installable"))
})

// インストールが終わったら、保存していた合図を捨ててボタンを隠す
window.addEventListener("appinstalled", () => {
  deferredInstallPrompt = null
  document.dispatchEvent(new CustomEvent("pwa-guide:installed"))
})

// -----------------------------------------------------------------------------
// 端末とブラウザの判定
// -----------------------------------------------------------------------------
//
// 【戻り値】
//   platform:     "inapp"（LINE などのアプリ内ブラウザ） / "ios" / "android" / "desktop"
//   isIOS:        iPhone / iPad なら true
//   isStandalone: ホーム画面（インストールしたアプリ）から開いていれば true
const detectEnvironment = () => {
  const ua = navigator.userAgent || ""

  // LINE のアプリ内ブラウザは User-Agent に "Line/バージョン" が入る。
  // \b（単語の区切り）を付けて、"Timeline/" のような別の文字列と区別する。
  // Facebook（FBAN / FBAV）・Instagram のアプリ内ブラウザも、ホーム画面に追加できない点が同じ。
  const isInApp = /\bLine\//i.test(ua) || /FBAN|FBAV|Instagram/i.test(ua)

  // iPad は「PC 版サイトを表示」が標準のため、User-Agent が Mac と同じになる。
  // Mac にはタッチ画面がないので、「Macintosh かつタッチ対応」なら iPad と判定する。
  const isIOS = /iPhone|iPad|iPod/i.test(ua) ||
                (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)

  const isAndroid = /Android/i.test(ua)

  // display-mode: standalone … Chrome / Edge / Android / iOS 共通の判定方法
  // navigator.standalone      … iPhone の Safari 独自の判定方法（古い iOS 向けの保険）
  const isStandalone =
    window.matchMedia("(display-mode: standalone)").matches ||
    window.navigator.standalone === true

  let platform = "desktop"
  if (isInApp) {
    platform = "inapp"
  } else if (isIOS) {
    platform = "ios"
  } else if (isAndroid) {
    platform = "android"
  }

  return { platform, isIOS, isStandalone }
}

export default class extends Controller {
  // targets（ビュー側の data-pwa-guide-target="..." と対応する）
  //   panel             : 端末ごとの手順（<details>）。data-platform で端末の種類を持つ
  //   standaloneOnly    : ホーム画面から開いているときだけ表示する要素
  //   iosStandaloneOnly : iPhone / iPad のホーム画面アプリのときだけ表示する要素
  //   browserOnly       : ブラウザで開いているときだけ表示する要素（手順の一覧など）
  //   installArea       : 「この端末にインストールする」ボタンの入れ物（Chrome / Edge のみ表示）
  static targets = ["panel", "standaloneOnly", "iosStandaloneOnly", "browserOnly", "installArea"]

  connect() {
    this.environment = detectEnvironment()

    this.showByDisplayMode()
    this.openPanelForThisDevice()
    this.updateInstallArea()

    // bind(this): イベントから呼ばれたときも this がこのコントローラーを指すようにする。
    // 同じ関数を disconnect() で外すため、変数に入れておく。
    this.boundUpdateInstallArea = this.updateInstallArea.bind(this)
    document.addEventListener("pwa-guide:installable", this.boundUpdateInstallArea)
    document.addEventListener("pwa-guide:installed", this.boundUpdateInstallArea)
  }

  disconnect() {
    // Turbo で別のページへ移動したときに、イベントの登録を外す（重複登録を防ぐ）
    document.removeEventListener("pwa-guide:installable", this.boundUpdateInstallArea)
    document.removeEventListener("pwa-guide:installed", this.boundUpdateInstallArea)
  }

  // ホーム画面から開いているかどうかで、表示する要素を切り替える
  //   hidden 属性: true で非表示、false で表示（Tailwind の preflight でも display: none になる）
  showByDisplayMode() {
    const { isStandalone, isIOS } = this.environment

    this.standaloneOnlyTargets.forEach((element) => {
      element.hidden = !isStandalone
    })
    this.iosStandaloneOnlyTargets.forEach((element) => {
      element.hidden = !(isStandalone && isIOS)
    })
    this.browserOnlyTargets.forEach((element) => {
      element.hidden = isStandalone
    })
  }

  // 使っている端末の手順だけを開き、「お使いの端末」の目印を付ける
  openPanelForThisDevice() {
    this.panelTargets.forEach((panel) => {
      const isThisDevice = panel.dataset.platform === this.environment.platform
      panel.open = isThisDevice

      // 目印（data-pwa-guide-badge が付いた span）は、該当する手順のときだけ表示する
      const badge = panel.querySelector("[data-pwa-guide-badge]")
      if (badge) badge.hidden = !isThisDevice
    })
  }

  // 「この端末にインストールする」ボタンを出すかどうか
  //   合図（beforeinstallprompt）を受け取っていて、まだホーム画面から開いていないときだけ出す
  updateInstallArea() {
    if (!this.hasInstallAreaTarget) return

    this.installAreaTarget.hidden =
      deferredInstallPrompt === null || this.environment.isStandalone
  }

  // ボタンが押されたら、ブラウザのインストール画面を出す
  //   async / await: 利用者が「インストール」か「キャンセル」を選ぶまで待つ
  async install() {
    const promptEvent = deferredInstallPrompt
    if (!promptEvent) {
      this.updateInstallArea()
      return
    }

    // 合図は1回しか使えないため、使う前に捨てておく
    deferredInstallPrompt = null

    try {
      await promptEvent.prompt()
      // userChoice: 利用者の選択（accepted / dismissed）が決まるまで待つ
      await promptEvent.userChoice
    } catch (_error) {
      // すでに使われた合図などで prompt() が失敗した場合は、
      // ボタンを隠すだけにする（下の手順を見てメニューから追加できる）
    }

    this.updateInstallArea()
  }
}