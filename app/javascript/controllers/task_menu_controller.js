// app/javascript/controllers/task_menu_controller.js
//
// ==============================================================================
// Stimulus コントローラー: タスク行の「⋯」メニュー + 削除確認モーダル（C-3）
// ==============================================================================
//
// 【設計方針】
//   B-5（習慣削除確認モーダル）と同じ設計パターンを採用する。
//   モーダル・ボトムシートは content_for :modals で </body> 直前に出力する。
//
//   理由:
//     タスクカードの div に transition-shadow（CSSのtransitionプロパティ）があると、
//     その子孫の fixed 要素が「画面全体」ではなく「カード要素」を基準に配置される。
//     CSSの仕様（スタッキングコンテキスト）による制約のため、
//     モーダルを body 直前に出力することで正しく全画面表示できる。
//
// 【表示/非表示の制御方法】
//   Tailwind の hidden クラスは「display: none !important」のため、
//   JS で style.display = "flex" を設定しても !important に負けて適用されない。
//   そのため、モーダルの初期状態を style="display: none" にして
//   JS で style.display を直接操作する方式を採用する。
//
// 【イベントリスナーを openMenu() で設定する理由】
//   content_for :modals はページ末尾（</body>直前）に出力される。
//   Stimulus の connect() が呼ばれる時点では、モーダルのDOMがまだ
//   存在しない場合があるため、connect()ではなく openMenu() 内で設定する。
//   _listenersAttached フラグで二重登録を防ぐ。
//
// 【Stimulus スコープ外のDOM操作について】
//   モーダルは data-controller="task-menu" の外側（body直前）に配置するため、
//   Stimulus の target は使えない。
//   代わりに getElementById() でDOMを直接取得して操作する。
//
// 【レビュー指摘対応 - C-3修正版】
//   ① disconnect() でイベントリスナーを削除するように修正
//      → Turboでページ遷移・再描画されたときにイベントが積み上がるのを防ぐ
//   ② openMenu() 内で削除フォームに tab の hidden input を動的追加
//      → サーバー側の destroy アクションで params[:tab] を正しく受け取れるようにする
//   ③ button_to に turbo_submits_with を追加（ERB側で対応）
//      → 削除ボタンの連打による二重送信を防ぐ
//
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ============================================================
  // static values（Stimulusの Values API）
  // ============================================================
  //
  // Values API は HTML の data-* 属性から値を型安全に取得する仕組み。
  // HTML側: data-task-menu-task-id-value="42"
  // JS側:   this.taskIdValue → 42（Number型として取得できる）
  //
  // taskId:
  //   タスクのID。モーダル・ボトムシートのDOM IDを構築するために使う。
  //   例: taskId=1 → モーダルの id="task-modal-1"
  //
  // taskTitle:
  //   タスク名。モーダルのタイトル（「○○を削除しますか？」）に表示する。
  //
  static values = {
    taskId:    Number,
    taskTitle: String
  }

  // ============================================================
  // connect()
  // ============================================================
  //
  // Stimulusのライフサイクルメソッド。
  // この data-controller が付いた要素がDOMに接続されたとき自動で呼ばれる。
  //
  // ここでは removeEventListener 用に bind済み関数を保存する。
  // bind(this) で this（コントローラーインスタンス）を固定した新しい関数を作る。
  // bind せずに addEventListener/removeEventListener に渡すと、
  // 「渡した関数の参照が毎回異なる」ため removeEventListener が機能しない。
  //
  connect() {
    this._boundCloseMenu    = this.closeMenu.bind(this)
    this._boundOverlayClick = this._handleOverlayClick.bind(this)
    this._listenersAttached = false
    this._stopProp          = (e) => e.stopPropagation()

    // ============================================================
    // 削除フォーム送信完了後にモーダルを自動で閉じる
    // ============================================================
    //
    // 【なぜ必要か】
    //   button_to で削除フォームを Turbo が送信・処理した後、
    //   タスク行は Turbo Stream で削除されるがモーダル自体は残る。
    //   document.body.style.overflow = "hidden" も残るため
    //   ページ全体がスクロールできなくなる。
    //
    // 【turbo:submit-end とは】
    //   Turbo がフォーム送信を完了したとき（成否問わず）に
    //   document に対して発火するカスタムイベント。
    //
    // 【_boundSubmitEnd を connect() で保存する理由】
    //   disconnect() で removeEventListener するために
    //   同じ関数参照が必要なため、bind した関数を保存する。
    //
    this._boundSubmitEnd = this._handleSubmitEnd.bind(this)
    document.addEventListener("turbo:submit-end", this._boundSubmitEnd)
  }

  // ============================================================
  // disconnect()
  // ============================================================
  //
  // ページ遷移時などにDOMから要素が削除されるとき自動で呼ばれる。
  //
  // 【レビュー指摘①対応】イベントリスナーを削除する
  //   イベントリスナーを削除しないと、Turboでページが再描画されるたびに
  //   同じ要素に対してリスナーが積み上がり（メモリリーク）、
  //   1回クリックしただけで closeMenu() が複数回呼ばれるバグになる。
  //
  disconnect() {
    // スクロール禁止を解除する
    document.body.style.overflow = ""

    // turbo:submit-end リスナーを削除する
    // connect() で登録したリスナーを必ず削除してメモリリークを防ぐ
    document.removeEventListener("turbo:submit-end", this._boundSubmitEnd)

    // イベントリスナーが未設定なら以降の削除処理をスキップ
    if (!this._listenersAttached) return

    const id = this.taskIdValue

    // デスクトップ用モーダルのリスナーを削除する
    const modal = document.getElementById(`task-modal-${id}`)
    if (modal) {
      modal.removeEventListener("click", this._boundOverlayClick)
      const panel = document.getElementById(`task-modal-panel-${id}`)
      if (panel) panel.removeEventListener("click", this._stopProp)
      const cancelBtn = document.getElementById(`task-modal-cancel-${id}`)
      if (cancelBtn) cancelBtn.removeEventListener("click", this._boundCloseMenu)
    }

    // スマホ用ボトムシートのリスナーを削除する
    const sheet = document.getElementById(`task-sheet-${id}`)
    if (sheet) {
      sheet.removeEventListener("click", this._boundOverlayClick)
      const panel = document.getElementById(`task-sheet-panel-${id}`)
      if (panel) panel.removeEventListener("click", this._stopProp)
      const cancelBtn = document.getElementById(`task-sheet-cancel-${id}`)
      if (cancelBtn) cancelBtn.removeEventListener("click", this._boundCloseMenu)
    }
  }

  // ============================================================
  // openMenu()
  // ============================================================
  //
  // 「⋯」ボタンをクリックしたとき呼ばれる。
  // data-action="click->task-menu#openMenu" から呼び出される。
  //
  // 処理の流れ:
  //   ① 初回のみイベントリスナーを設定する
  //   ② モーダルのタイトルをタスク名に更新する
  //   ③ 削除フォームに現在のタブを hidden input として追加する（レビュー指摘②対応）
  //   ④ 背景スクロールを禁止する
  //   ⑤ 画面幅に応じてモーダルかボトムシートを表示する
  //
  openMenu() {
    // ① 初回のみリスナーを設定する（_listenersAttached でフラグ管理）
    if (!this._listenersAttached) {
      this._setupListeners()
      this._listenersAttached = true
    }

    // ② モーダルタイトルを更新する
    this._updateModalTitle()

    // ③ 削除フォームに現在のタブを追加する
    //    destroy アクションで params[:tab] を受け取るために必要。
    //    tab がないとリダイレクト先が tasks_path(tab: nil) になり
    //    「全て」タブに戻ってしまう（意図した動作ではないことがある）。
    this._injectTabToForms()

    // ④ 背景スクロールを禁止する
    document.body.style.overflow = "hidden"

    // ⑤ 画面幅で表示するUIを切り替える
    //    768px 以上（md ブレイクポイント）→ デスクトップ用中央モーダル
    //    768px 未満                         → スマホ用ボトムシート
    if (window.innerWidth >= 768) {
      this._openDesktopModal()
    } else {
      this._openBottomSheet()
    }
  }

  // ============================================================
  // closeMenu()
  // ============================================================
  //
  // モーダル・ボトムシートを閉じる。
  // キャンセルボタン・オーバーレイクリック・Escapeキーから呼ばれる。
  //
  closeMenu() {
    this._closeDesktopModal()
    this._closeBottomSheet()
    // スクロール禁止を解除する
    document.body.style.overflow = ""
  }

  // ============================================================
  // keydown(event)
  // ============================================================
  //
  // Escape キーでモーダルを閉じる（アクセシビリティ対応）。
  //
  // data-action="keydown@window->task-menu#keydown" から呼ばれる。
  // @window はウィンドウ全体のキーボードイベントを監視する指定。
  // モーダル外にフォーカスがあっても Escape で閉じられる。
  //
  keydown(event) {
    if (event.key === "Escape") {
      this.closeMenu()
    }
  }

  // ============================================================
  // Private メソッド
  // ============================================================

  // ----------------------------------------------------------
  // _setupListeners()
  // ----------------------------------------------------------
  //
  // モーダル・ボトムシートにイベントリスナーを設定する。
  //
  // ① モーダル全体（オーバーレイ部分）クリック → closeMenu()
  // ② パネル内クリック → stopPropagation（モーダルが閉じないようにする）
  //    パネル（白い部分）のクリックがオーバーレイまで伝播すると
  //    パネル内クリックでもモーダルが閉じてしまうため、伝播を止める。
  // ③ キャンセルボタンクリック → closeMenu()
  //
  // 【connect() で _stopProp を定義している理由】
  //   disconnect() で removeEventListener するために同じ関数参照が必要。
  //   ここで新しく (e) => e.stopPropagation() を作ると
  //   disconnect() で参照できないため、connect() で保存した this._stopProp を使う。
  //
  _setupListeners() {
    const id = this.taskIdValue

    // ── デスクトップ用モーダル ──────────────────────────────────────────
    const modal = document.getElementById(`task-modal-${id}`)
    if (modal) {
      // ① オーバーレイクリックで閉じる
      modal.addEventListener("click", this._boundOverlayClick)

      // ② パネル内クリックの伝播をブロックする
      const panel = document.getElementById(`task-modal-panel-${id}`)
      if (panel) panel.addEventListener("click", this._stopProp)

      // ③ キャンセルボタンで閉じる
      const cancelBtn = document.getElementById(`task-modal-cancel-${id}`)
      if (cancelBtn) cancelBtn.addEventListener("click", this._boundCloseMenu)
    }

    // ── スマホ用ボトムシート ────────────────────────────────────────────
    const sheet = document.getElementById(`task-sheet-${id}`)
    if (sheet) {
      sheet.addEventListener("click", this._boundOverlayClick)

      const panel = document.getElementById(`task-sheet-panel-${id}`)
      if (panel) panel.addEventListener("click", this._stopProp)

      const cancelBtn = document.getElementById(`task-sheet-cancel-${id}`)
      if (cancelBtn) cancelBtn.addEventListener("click", this._boundCloseMenu)
    }
  }

  // ----------------------------------------------------------
  // _handleOverlayClick()
  // ----------------------------------------------------------
  //
  // オーバーレイ（モーダル背景の暗い部分）がクリックされたときに呼ばれる。
  //
  // _stopProp でパネル内クリックの伝播を止めているため、
  // このメソッドが呼ばれる = 確実にオーバーレイがクリックされた。
  //
  _handleOverlayClick() {
    this.closeMenu()
  }

  // ----------------------------------------------------------
  // _handleSubmitEnd(event)
  // ----------------------------------------------------------
  //
  // Turbo がフォーム送信を完了したときに呼ばれる。
  //
  // 【event.detail.formSubmission.formElement について】
  //   turbo:submit-end の detail.formSubmission.formElement に
  //   送信された <form> 要素が入っている。
  //   フォームの id で「自分のタスクの削除フォームか」を判定する。
  //
  // 【なぜ document 全体を監視するのか】
  //   削除フォームは content_for :modals で body 直前に出力されるため
  //   Stimulus のスコープ（data-controller の要素）の外にある。
  //   そのため this.element ではなく document に登録する必要がある。
  //
  // 【なぜフォームIDで絞り込むのか】
  //   document 全体を監視しているため、他のフォーム送信でも
  //   このメソッドが呼ばれる。自分のタスクの削除フォームのときだけ
  //   closeMenu() を呼ぶためにフォームIDで判定する。
  //
  _handleSubmitEnd(event) {
    const id   = this.taskIdValue
    const form = event.detail?.formSubmission?.formElement

    if (!form) return

    // デスクトップ用フォームかスマホ用フォームの送信完了なら閉じる
    if (form.id === `task-delete-form-${id}` ||
        form.id === `task-delete-sheet-form-${id}`) {
      this.closeMenu()
    }
  }

  // ----------------------------------------------------------
  // _updateModalTitle()
  // ----------------------------------------------------------
  //
  // モーダルとボトムシートのタイトルをタスク名に更新する。
  // .js-task-menu-title クラスで対象要素を特定する。
  //
  _updateModalTitle() {
    const id   = this.taskIdValue
    const text = `「${this.taskTitleValue}」を削除しますか？`

    // デスクトップ用モーダルのタイトルを更新する
    const modalTitle = document.querySelector(`#task-modal-${id} .js-task-menu-title`)
    if (modalTitle) modalTitle.textContent = text

    // スマホ用ボトムシートのタイトルを更新する
    const sheetTitle = document.querySelector(`#task-sheet-${id} .js-task-menu-title`)
    if (sheetTitle) sheetTitle.textContent = text
  }

  // ----------------------------------------------------------
  // _injectTabToForms()
  // ----------------------------------------------------------
  //
  // 【レビュー指摘②対応】
  // 削除フォームに現在のタブを hidden input として動的に追加する。
  //
  // 【なぜ必要か】
  //   _task_row.html.erb はパーシャルのため、レンダリング時点では
  //   現在のタブ（?tab=must など）の情報を持っていない。
  //   そのため、ERB側でフォームに tab を静的に埋め込めない。
  //   代わりにモーダルを開くとき（openMenu()）に
  //   URL のクエリパラメータから tab を取得してフォームに追加する。
  //
  // 【URLSearchParams とは】
  //   ブラウザ標準のAPI。URL のクエリ文字列（?以降）をパースする。
  //   例: /tasks?tab=must → params.get("tab") → "must"
  //   例: /tasks         → params.get("tab") → null（タブ指定なし）
  //
  // 【既存の hidden input を上書きする理由】
  //   2回目以降に openMenu() を呼んだとき（タブを変えて再度開く場合）、
  //   古い tab の値が残らないように既存の input を上書きする。
  //
  _injectTabToForms() {
    // 現在の URL から tab パラメータを取得する
    const tab = new URLSearchParams(window.location.search).get("tab")

    // tab が指定されていない場合は追加しない（サーバー側のデフォルト "all" が使われる）
    if (!tab) return

    const id = this.taskIdValue

    // デスクトップ用フォームと スマホ用フォームの両方に追加する
    const formIds = [
      `task-delete-form-${id}`,
      `task-delete-sheet-form-${id}`
    ]

    formIds.forEach(formId => {
      const form = document.getElementById(formId)
      if (!form) return

      // 既存の tab hidden input を探す
      let input = form.querySelector("input[name='tab']")

      // なければ新しく作る
      if (!input) {
        input = document.createElement("input")
        input.type = "hidden"
        input.name = "tab"
        form.appendChild(input)
      }

      // 値をセットする（2回目以降は上書き）
      input.value = tab
    })
  }

  // ----------------------------------------------------------
  // _openDesktopModal() / _closeDesktopModal()
  // ----------------------------------------------------------
  //
  // 【なぜ style.display を直接操作するのか】
  //   Tailwind の hidden クラス（display: none !important）は
  //   後から style.display = "flex" を設定しても !important に負けて無効になる。
  //   そのため、モーダルの初期状態を style="display: none" にして
  //   JS で style.display を直接切り替える方式を採用している。
  //
  _openDesktopModal() {
    const modal = document.getElementById(`task-modal-${this.taskIdValue}`)
    if (!modal) return

    // フレックスコンテナとして表示する（items-center justify-center で中央揃えになる）
    modal.style.display = "flex"

    // モーダル内の最初のボタンにフォーカスを移す（アクセシビリティ対応）
    // setTimeout(0) でブラウザのレンダリングが完了した後にフォーカスする
    setTimeout(() => {
      const firstButton = modal.querySelector("button")
      if (firstButton) firstButton.focus()
    }, 0)
  }

  _closeDesktopModal() {
    const modal = document.getElementById(`task-modal-${this.taskIdValue}`)
    if (!modal) return
    modal.style.display = "none"
  }

  // ----------------------------------------------------------
  // _openBottomSheet() / _closeBottomSheet()
  // ----------------------------------------------------------
  //
  // CSSトランジションでボトムシートをスライドイン/アウトする。
  //
  // スライドインの仕組み:
  //   ① style.display = "flex" でボトムシート全体を表示する
  //   ② setTimeout(10) で10ms後にパネルの translate-y-full を削除して
  //      translate-y-0 を追加する
  //      → 「画面外（下）→ 定位置」へのスライドアニメーションが発生する
  //   10ms 待つ理由: ブラウザがdisplay変更後に初期状態を描画するのを待つ。
  //   0ms だとtranslate-y-fullの状態が描画される前にtranslate-y-0になり
  //   アニメーションが見えない。
  //
  _openBottomSheet() {
    const id    = this.taskIdValue
    const sheet = document.getElementById(`task-sheet-${id}`)
    if (!sheet) return

    // ① まずボトムシート全体（背景overlay）を表示する
    sheet.style.display = "flex"

    // ② 少し遅らせてからパネルをスライドインさせる
    setTimeout(() => {
      const panel = document.getElementById(`task-sheet-panel-${id}`)
      if (panel) {
        panel.classList.remove("translate-y-full")
        panel.classList.add("translate-y-0")
      }
    }, 10)
  }

  _closeBottomSheet() {
    const id = this.taskIdValue

    // パネルを画面下にスライドアウトする
    const panel = document.getElementById(`task-sheet-panel-${id}`)
    if (panel) {
      panel.classList.remove("translate-y-0")
      panel.classList.add("translate-y-full")
    }

    // アニメーション完了後（300ms）にボトムシート全体を非表示にする
    // 非表示を先にするとアニメーション中に要素が消えて不自然になる
    setTimeout(() => {
      const sheet = document.getElementById(`task-sheet-${id}`)
      if (sheet) sheet.style.display = "none"
    }, 300)
  }
}