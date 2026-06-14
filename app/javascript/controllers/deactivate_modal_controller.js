// app/javascript/controllers/deactivate_modal_controller.js
//
// ==============================================================================
// DeactivateModalController: 退会確認モーダル（M-4）制御（H-2対応版）
// ==============================================================================
//
// 【H-2 で変更した内容】
//   旧実装の問題点:
//     ① HTML側が <div hidden> (HTML属性)、JS側が classList.remove("hidden")
//        → HTML属性の hidden は classList では操作できないため、
//          モーダルが開かない致命的バグがあった。
//     ② スマホでも中央モーダルのままで、ボトムシート未対応だった。
//
//   変更内容:
//     ① HTML側の hidden 属性を class="hidden" に統一し、
//        JS から classList で安全に制御できるようにした。
//     ② target を使った構造に変更し、スマホ用ボトムシートを追加した。
//     ③ スワイプダウン（touchstart/touchmove/touchend）で閉じる機能を追加した。
//     ④ Escape キー対応・disconnect() でのメモリリーク防止を追加した。
//
// 【設計方針】
//   M-4 モーダルは settings/show.html.erb の
//   data-controller="deactivate-modal" スコープ内に配置されているため、
//   他のモーダル（M-1〜M-3）と異なり getElementById は不要で、
//   Stimulus の target / action をそのまま使える。
//
// 【なぜ hidden クラスで統一するのか】
//   HTML 属性の hidden（<div hidden>）と
//   Tailwind の hidden クラス（class="hidden"）は別物。
//   HTML 属性は JS の classList では操作できない。
//   → HTML 側を class="hidden" に統一することで JS から安全に制御できる。
//
// 【ボトムシートのアニメーション仕組み】
//   open 時:
//     1. overlayTarget の class="hidden" を外す
//     2. 画面幅で desktopPanel か mobileSheet を表示
//     3. スマホの場合: 10ms 後に translate-y-full を translate-y-0 に変更
//        → CSS transition により下からスライドインするアニメーション発生
//   close 時:
//     1. translate-y-0 を translate-y-full に戻す（スライドアウト）
//     2. 300ms 後（アニメーション完了後）に class="hidden" を戻す
//     ※ 300ms は CSS の transition-duration と合わせる
//
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ============================================================
  // static targets
  // ============================================================
  //
  // HTML 側で data-deactivate-modal-target="xxx" と書いた要素を
  // this.xxxTarget で参照できるようになる。
  //
  // 【各ターゲットの役割】
  //   overlay      : モーダル全体のラッパー（初期状態: class="hidden"）
  //                  open() で hidden を外し、close() で hidden を戻す
  //   desktopPanel : デスクトップ用の中央配置カード（768px 以上で表示）
  //   mobileSheet  : スマホ用ボトムシートのコンテナ（768px 未満で表示）
  //   sheetPanel   : スマホ用ボトムシートの白いカード部分
  //                  transform アニメーションとスワイプジェスチャーの対象
  //
  static targets = [
    "overlay",       // 全体ラッパー（半透明背景 + コンテンツを包む固定レイヤー）
    "desktopPanel",  // デスクトップ用モーダルカード
    "mobileSheet",   // スマホ用ボトムシートコンテナ（items-end で下端配置）
    "sheetPanel"     // スマホ用ボトムシートのカード（スライドアニメーション対象）
  ]

  // ============================================================
  // connect(): Stimulus がこのコントローラーを DOM に接続したとき自動実行
  // ============================================================
  //
  // 【タイマー ID の初期化】
  //   close() 内の setTimeout の ID を保存して管理する。
  //   disconnect() でキャンセルできるようにするために必要。
  //
  // 【スワイプ用変数の初期化】
  //   touchstart で記録した指の初期 Y 座標を保持する変数。
  //
  // 【Escape キーリスナーの登録】
  //   bind(this) で this（コントローラーインスタンス）を固定した関数を作る。
  //   disconnect() で removeEventListener する際に同じ関数参照が必要なため保存する。
  //
  connect() {
    // close() の setTimeout の ID を管理する（二重呼び出し防止用）
    this._closeTimer = null

    // スワイプジェスチャー用の座標変数を初期化する
    // touchstart で記録した指の Y 座標（画面上端からのピクセル数）
    this._startY = 0
    // touchmove で更新し続ける現在の Y 座標
    this._currentY = 0

    // Escape キーでモーダルを閉じるイベントリスナーを登録する
    // bind(this) で「this」をこのコントローラーに固定する
    this._boundKeydown = this._handleKeydown.bind(this)
    document.addEventListener("keydown", this._boundKeydown)
  }

  // ============================================================
  // disconnect(): コントローラーが DOM から切り離されたとき自動実行
  // ============================================================
  //
  // 【なぜイベントリスナーを削除するのか】
  //   Turbo Drive でページ遷移してもリスナーが残り続けると
  //   「メモリリーク」（不要なデータが残り動作が重くなる）が発生する。
  //   disconnect() で必ず削除して安全な状態にする。
  //
  disconnect() {
    // keydown リスナーを削除する
    document.removeEventListener("keydown", this._boundKeydown)

    // 実行中のタイマーをキャンセルする
    if (this._closeTimer) {
      clearTimeout(this._closeTimer)
      this._closeTimer = null
    }

    // モーダルが開いたままページ遷移した場合に備えてスクロール禁止を解除する
    document.body.classList.remove("overflow-hidden")
  }

  // ============================================================
  // open(): モーダルを開く
  // ============================================================
  //
  // 【HTML での呼び出し方】
  //   <button data-action="click->deactivate-modal#open">退会する</button>
  //
  // 【処理の流れ】
  //   1. overlayTarget の class="hidden" を外して DOM に表示させる
  //   2. 背景スクロールを禁止する（モーダル表示中は背景が動くと UX が悪い）
  //   3. 画面幅で表示方式を切り替える
  //      768px 以上 → デスクトップ用中央モーダル
  //      768px 未満 → スマホ用ボトムシート
  //
  open() {
    // 閉じるアニメーション中に再度開かれた場合、タイマーをキャンセルする
    // close() の setTimeout(300ms) が完了すると transition="none" が設定されてしまうため
    if (this._closeTimer) {
      clearTimeout(this._closeTimer)
      this._closeTimer = null
    }

    // ① overlay の class="hidden" を外して表示可能な状態にする
    //   （fixed inset-0 z-[60] のレイヤーが画面全体を覆うようになる）

    // ② モーダル表示中は背景スクロールをロックする
    document.body.classList.add("overflow-hidden")

    // ③ 画面幅で表示方式を切り替える
    if (window.innerWidth >= 768) {
      this._openDesktop()
    } else {
      this._openMobile()
    }
  }

  // ============================================================
  // close(): モーダルを閉じる
  // ============================================================
  //
  // 【HTML での呼び出し方】
  //   <button data-action="click->deactivate-modal#close">キャンセル</button>
  //
  // 【処理の流れ】
  //   1. スマホ用ボトムシートのスライドアウトアニメーションを開始する
  //   2. 300ms 後（CSS transition と同じ時間）に overlay を hidden に戻す
  //   ※ デスクトップの場合は _closeMobile() が sheetPanel を持たないため安全にスキップ
  //
  close() {
    // 二重呼び出しでタイマーが重複しないようキャンセルする
    if (this._closeTimer) {
      clearTimeout(this._closeTimer)
      this._closeTimer = null
    }

    // スマホ用ボトムシートをスライドアウトさせる
    // （デスクトップでは hasSheetPanelTarget が false のため何もしない）

    // CSS transition の時間（300ms）が終わってから overlay を非表示にする
    // 先に hidden にするとアニメーション中に消えて不自然になる
    this._closeTimer = setTimeout(() => {
      this.overlayTarget.style.display = ""
      this.overlayTarget.classList.add("hidden")
      if (this.hasDesktopPanelTarget) {
        this.desktopPanelTarget.style.display = ""
        this.desktopPanelTarget.classList.add("hidden")
      }
      if (this.hasMobileSheetTarget) {
        this.mobileSheetTarget.style.display = "none"
      }
      // sheetPanel を完全に初期状態（translate-y-full）に戻す
      // インライン transition も含めて完全リセットする
      // （touchEnd で style.transition = "transform 0.3s ease-out" が残る場合があるため）
      if (this.hasSheetPanelTarget) {
        this.sheetPanelTarget.style.transform = ""
        this.sheetPanelTarget.style.transition = ""
        this.sheetPanelTarget.classList.remove("translate-y-0")
        this.sheetPanelTarget.classList.add("translate-y-full")
      }
      document.body.classList.remove("overflow-hidden")
      this._closeTimer = null
    }, 300)
  }

  // ============================================================
  // closeFromOverlay(event): バックドロップ（暗幕）タップで閉じる
  // ============================================================
  //
  // 【HTML での呼び出し方】
  //   <div data-action="click->deactivate-modal#closeFromOverlay">暗幕</div>
  //
  // 【event.target チェックの理由】
  //   モーダルカード内のクリックが「バブリング」（イベントが親要素へ伝播）して
  //   バックドロップまで届くことがある。
  //   event.target（実際にクリックした要素）と
  //   event.currentTarget（このリスナーが登録された要素）が
  //   同じ場合だけ閉じることで、誤閉じを防ぐ。
  //
  closeFromOverlay(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }

  // ============================================================
  // touchStart(event): スワイプ開始 — 指が画面に触れた瞬間
  // ============================================================
  //
  // 【HTML での呼び出し方】
  //   <div data-action="touchstart->deactivate-modal#touchStart ...">
  //
  // 【処理】
  //   指が触れた Y 座標を記録する。
  //   CSS transition を一時的にオフにして、
  //   指の動きにリアルタイムで追従できるようにする。
  //
  touchStart(event) {
    // touches[0] は「最初の指」の情報。clientY は画面上端からの縦位置（px）
    this._startY   = event.touches[0].clientY
    this._currentY = event.touches[0].clientY

    // 指の動きに即座に反応させるため、CSS のアニメーション（transition）を一時的に無効にする
    // これを外さないと「transition のせいで指より遅れてシートが動く」ぎこちない動きになる
    if (this.hasSheetPanelTarget) {
      this.sheetPanelTarget.style.transition = "none"
    }
  }

  // ============================================================
  // touchMove(event): スワイプ中 — 指を動かしている間ずっと呼ばれる
  // ============================================================
  //
  // 【処理】
  //   下方向への移動量（deltaY）を計算して
  //   シートを指の動きにリアルタイムで追従させる。
  //   上方向への引っ張りは無視する（下方向だけ反応）。
  //
  // 【preventDefault() の重要性】
  //   呼ばないと「指でシートを引っ張りながら背景ページもスクロールする」
  //   二重スクロールが発生する（特に iOS Safari で顕著）。
  //   preventDefault() でブラウザのデフォルトスクロールをキャンセルする。
  //   ただし passive リスナーでは preventDefault() が使えないため、
  //   HTML 側の data-action で touchmove を登録する際に
  //   Rails/Hotwire の passive オプションは指定しない（デフォルトで non-passive）。
  //
  touchMove(event) {
    this._currentY = event.touches[0].clientY

    // 指がどれだけ下に移動したか（px）
    // プラスの値 = 下方向、マイナスの値 = 上方向
    const deltaY = this._currentY - this._startY

    // 下方向へのスワイプのときだけシートを追従させる
    if (deltaY > 0 && this.hasSheetPanelTarget) {
      // ブラウザのデフォルトスクロールをキャンセルする（iOS Safari 対策）
      event.preventDefault()
      // シートを指と同じ距離だけ下にずらす（リアルタイム追従）
      this.sheetPanelTarget.style.transform = `translateY(${deltaY}px)`
    }
  }

  // ============================================================
  // touchEnd(event): スワイプ終了 — 指が画面から離れた瞬間
  // ============================================================
  //
  // 【処理】
  //   移動量（deltaY）が 120px 以上なら「十分に引き下げた」と判断して閉じる。
  //   120px 未満なら「少し触れただけ」と判断して元の位置に戻す。
  //
  // 【120px の根拠】
  //   一般的なモバイル UI では画面高さの 20〜30% が判定基準。
  //   100px だと誤判定が多く、150px だと閉じにくい。
  //   120px はその中間で一般的な実装に合わせた値。
  //
  touchEnd(event) {
    const deltaY = this._currentY - this._startY

    if (this.hasSheetPanelTarget) {
      // 指が離れたので CSS transition を再度有効にしてアニメーションを復活させる
      this.sheetPanelTarget.style.transition = "transform 0.3s ease-out"
    }

    if (deltaY > 120) {
      // 十分に引き下げた → そのまま閉じる
      // close() の _closeMobile() が translate-y-full を追加するが、
      // その前にインラインの transform をクリアして translate クラスと競合しないようにする
      if (this.hasSheetPanelTarget) {
        this.sheetPanelTarget.style.transform = ""
        this.sheetPanelTarget.style.transition = ""
      }
      this.close()
    } else {
      // 引き下げ量が少ない → 元の定位置（translateY(0)）に戻す
      if (this.hasSheetPanelTarget) {
        this.sheetPanelTarget.style.transform = "translateY(0)"
      }
    }
  }

  // ============================================================
  // Private メソッド（このコントローラー内部でのみ使う処理）
  // ============================================================

  // ----------------------------------------------------------
  // _openDesktop(): デスクトップ用中央モーダルを表示する
  // ----------------------------------------------------------
  //
  // overlay の display を flex にして、
  // その中の desktopPanel を flex で表示する。
  // （overlay に fixed inset-0 があるため画面全体を覆う）
  //
  _openDesktop() {
    // overlay を flex で表示する（hidden クラスはすでに open() で外れている）
    this.overlayTarget.style.display = "flex"

    // デスクトップ用パネルを flex で表示する
    // （fixed inset-0 flex items-center justify-center で中央配置になる）
    if (this.hasDesktopPanelTarget) {
      this.desktopPanelTarget.classList.remove("hidden")
      this.desktopPanelTarget.style.display = "flex"
    }

    // スマホ用シートは念のため非表示にする
    // （画面幅が変わって open() を再度呼んだとき状態が残らないようにする）
    if (this.hasMobileSheetTarget) {
      this.mobileSheetTarget.style.display = "none"
    }

    // モーダルが開いた直後に最初のボタンにフォーカスを移す（アクセシビリティ対応）
    // setTimeout(0) でブラウザのレンダリングが完了してからフォーカスする
    setTimeout(() => {
      if (this.hasDesktopPanelTarget) {
        const firstButton = this.desktopPanelTarget.querySelector("button")
        if (firstButton) firstButton.focus()
      }
    }, 0)
  }

  // ----------------------------------------------------------
  // _openMobile(): スマホ用ボトムシートを表示する
  // ----------------------------------------------------------
  //
  // 【スライドインの仕組み】
  //   1. mobileSheet を flex で表示する（items-end でコンテンツが下端に配置）
  //   2. 10ms 後に sheetPanel の translate-y-full を translate-y-0 に変更
  //      → CSS transition（duration-300）により下からスライドインするアニメーション発生
  //
  // 【10ms 待つ理由】
  //   display: flex に変更した直後に classList を変更すると、
  //   ブラウザが translate-y-full の初期状態を描画する前に translate-y-0 になり、
  //   アニメーションが発生しない（いきなり定位置に現れる）。
  //   10ms 待つことでブラウザが1フレーム描画してからアニメーションが開始する。
  //
  _openMobile() {
    this.overlayTarget.style.display = "flex"
    if (this.hasDesktopPanelTarget) this.desktopPanelTarget.style.display = "none"
    if (this.hasMobileSheetTarget)  this.mobileSheetTarget.style.display = "flex"

    if (this.hasSheetPanelTarget) {
      // インラインスタイルを完全クリアしてクラスのみで制御する
      this.sheetPanelTarget.style.cssText = ""
      this.sheetPanelTarget.classList.remove("translate-y-0")
      this.sheetPanelTarget.classList.add("translate-y-full")
      // scrollTop をリセットして次回open時に先頭から表示する
      this.sheetPanelTarget.scrollTop = 0
    }

    // requestAnimationFrame で確実に1フレーム描画後にスライドイン開始
    // translate-y-full の状態をブラウザが描画してからアニメーションを開始する
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (this.hasSheetPanelTarget) {
          this.sheetPanelTarget.classList.remove("translate-y-full")
          this.sheetPanelTarget.classList.add("translate-y-0")
        }
      })
    })
  }

  // ----------------------------------------------------------
  // _closeMobile(): スマホ用ボトムシートをスライドアウトさせる
  // ----------------------------------------------------------
  //
  // 【スライドアウトの仕組み】
  //   translate-y-0（定位置）→ translate-y-full（画面外・下）に変更
  //   → CSS transition により下にスライドアウトするアニメーション発生
  //   → 300ms 後（close() の setTimeout）に overlay が hidden に戻る
  //
  // 【デスクトップでも呼ばれる理由】
  //   close() から無条件で呼ばれるが、
  //   hasSheetPanelTarget チェックにより sheetPanel がない場合は何もしないので安全。
  //
  _closeMobile() {
    if (this.hasSheetPanelTarget) {
      // インラインスタイルをクリアして translate クラスとの競合を防ぐ
      // （touchEnd でインラインの transform が残っている場合があるため）
      // インラインの transform のみクリアし、transition はクリアしない
      // transition をクリアするとスライドアウトアニメーションが消えてしまう
      // CSS クラスの transition-transform duration-300 に任せる
      this.sheetPanelTarget.style.transform = ""

      // translate-y-0（定位置）を外して translate-y-full（画面外・下）を追加
      // → CSS の transition-transform duration-300 により下にスライドアウト
      this.sheetPanelTarget.classList.remove("translate-y-0")
      this.sheetPanelTarget.classList.add("translate-y-full")
    }
  }

  // ----------------------------------------------------------
  // _handleKeydown(event): Escape キーでモーダルを閉じる
  // ----------------------------------------------------------
  //
  // 【アクセシビリティ対応】
  //   WCAG 2.1 達成基準 2.1.1（キーボード操作）に対応するため、
  //   Escape キーでモーダルを閉じられるようにする。
  //   スクリーンリーダーユーザーやキーボード操作ユーザーのために必要。
  //
  _handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}