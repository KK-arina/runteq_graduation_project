// app/javascript/controllers/ai_proposal_modal_controller.js
//
// ==============================================================================
// AiProposalModalController（E-3 修正版）
// ==============================================================================
//
// 【E-3修正での変更内容】
//   ① open(event) / close(event) 等に event 引数を追加（将来の preventDefault() 対応）
//   ② ESC キーでモーダルを閉じる機能を追加
//   ③ document.body.style.overflow → document.body.classList で管理
//      （他モーダルとの競合を防ぐ classList ベースに変更）
//   ④ dismissTask() で card.remove() + checkbox.disabled = true に変更
//      （display:none だけだとTurbo復元時に復活する問題を修正）
//   ⑤ disconnect() に classList.remove("overflow-hidden") を追加
//      （Turboキャッシュ経由でページ復元したときのスクロールロック残留を防ぐ）
//
// 【アクション一覧】
//   open(event)               : モーダルを表示する
//   close(event)              : モーダルを閉じる
//   closeFromOverlay(event)   : オーバーレイクリックで閉じる
//   openReanalyzeConfirm(event): 「編集して再解析」確認ダイアログを開く
//   closeReanalyzeConfirm(event): 確認ダイアログを閉じる
//   dismissTask(event)        : タスク提案をリストから除外する
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ============================================================
  // static targets
  // ============================================================
  //
  // Stimulus の target は data-{controller}-target="{name}" で DOM 要素を参照する。
  // wrapper:          モーダル全体のラッパー div（hidden 属性を切り替える）
  // reanalyzeConfirm: 「編集して再解析」確認ダイアログ
  // form:             提案フォーム（全選択等の将来拡張用）
  static targets = ["wrapper", "reanalyzeConfirm", "form"]

  // ============================================================
  // connect()
  // ============================================================
  //
  // Stimulus ライフサイクルメソッド。コントローラーが DOM に接続したとき自動で呼ばれる。
  //
  // 登録するイベントリスナー:
  //   ① 'open-ai-proposal-modal': index.html.erb のバナーボタンからモーダルを開く
  //      window.dispatchEvent(new CustomEvent('open-ai-proposal-modal')) で発火する。
  //   ② 'keydown': ESC キーでモーダルを閉じる（修正②）
  //
  // bind(this) の理由:
  //   addEventListener のコールバック内で this がコントローラーを指すようにする。
  //   bind なしだと this が window になって wrapperTarget にアクセスできない。
  //
  // disconnect() で必ず removeEventListener する理由:
  //   Turbo ではページ遷移時に DOM が再構成されるが window リスナーは残り続ける。
  //   複数回 connect/disconnect されると多重登録になってメモリリークになる。
  connect() {
    // ① window カスタムイベントリスナー（バナーボタンからモーダルを開く）
    this.openHandler = this.open.bind(this)
    window.addEventListener("open-ai-proposal-modal", this.openHandler)

    // ② ESC キーリスナー（修正②: ESCキー対応を追加）
    //    keydown イベントで event.key === "Escape" のときだけ close() を呼ぶ。
    this.escapeHandler = (event) => {
      if (event.key === "Escape") {
        this.close(event)
      }
    }
    window.addEventListener("keydown", this.escapeHandler)
  }

  // ============================================================
  // disconnect()
  // ============================================================
  //
  // Stimulus ライフサイクルメソッド。コントローラーが DOM から切り離されたとき自動で呼ばれる。
  //
  // 【修正⑤: classList.remove を追加】
  //   Turboキャッシュでページが復元されたとき、モーダルが閉じた状態でも
  //   overflow-hidden クラスが body に残ってスクロールできなくなる問題を防ぐ。
  disconnect() {
    window.removeEventListener("open-ai-proposal-modal", this.openHandler)
    window.removeEventListener("keydown", this.escapeHandler)

    // Turbo キャッシュ復元時のスクロールロック残留を防ぐ（修正⑤）
    document.body.classList.remove("overflow-hidden")
  }

  // ============================================================
  // open(event)
  // ============================================================
  //
  // モーダルを表示する。
  //
  // 【修正①: event 引数を追加】
  //   将来的に event.preventDefault() や event.stopPropagation() を
  //   追加したくなったときに対応できるよう、最初から引数を受け取る設計にする。
  //
  // 【修正③: classList.add("overflow-hidden")】
  //   変更前: document.body.style.overflow = 'hidden'
  //     → 他のモーダル（crisis_intervention 等）が overflow を管理している場合に競合する。
  //     → モーダルを閉じるときに 'auto' に戻すと、別のモーダルが開いていても解除される。
  //   変更後: document.body.classList.add("overflow-hidden")
  //     → クラスの付け外しで管理するため、複数のモーダルが共存しても安全。
  //     → Tailwind の overflow-hidden クラスが適用される（CSS: overflow: hidden）。
  open(event) {
    if (this.hasWrapperTarget) {
      this.wrapperTarget.removeAttribute("hidden")

      // overflow-hidden クラスで背景スクロールをロックする（修正③）
      document.body.classList.add("overflow-hidden")

      // フォーカスを最初のフォーカス可能要素に移動する（アクセシビリティ対応）
      // モーダルが開いたとき、キーボードユーザーがすぐに操作できるようにする。
      const firstFocusable = this.wrapperTarget.querySelector(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
      if (firstFocusable) firstFocusable.focus()
    }
  }

  // ============================================================
  // close(event)
  // ============================================================
  //
  // モーダルを閉じる。
  //
  // 【修正①: event 引数を追加】
  // 【修正③: classList.remove("overflow-hidden")】
  //   overflow を 'auto' に戻す代わりにクラスを除去する。
  //   他のモーダルが overflow-hidden を必要としている場合に影響しない。
  close(event) {
    if (this.hasWrapperTarget) {
      this.wrapperTarget.setAttribute("hidden", "")

      // overflow-hidden クラスを除去してスクロールロックを解除する（修正③）
      document.body.classList.remove("overflow-hidden")
    }

    // 確認ダイアログが開いている場合も一緒に閉じる
    this.closeReanalyzeConfirm()
  }

  // ============================================================
  // closeFromOverlay(event)
  // ============================================================
  //
  // オーバーレイ（背景の暗幕）クリックでモーダルを閉じる。
  //
  // 【修正①: event 引数を追加】
  // 【元の実装から簡略化】
  //   元の実装では if (e.target === e.currentTarget) の条件があったが、
  //   オーバーレイ div には子要素がないため条件は常に true になる。
  //   シンプルに close() を呼ぶだけで十分。
  closeFromOverlay(event) {
    this.close(event)
  }

  // ============================================================
  // openReanalyzeConfirm(event)
  // ============================================================
  //
  // 「編集して再解析」ボタンをクリックしたとき確認ダイアログを表示する。
  // 【修正①: event 引数を追加】
  openReanalyzeConfirm(event) {
    if (this.hasReanalyzeConfirmTarget) {
      this.reanalyzeConfirmTarget.removeAttribute("hidden")
    }
  }

  // ============================================================
  // closeReanalyzeConfirm(event)
  // ============================================================
  //
  // 確認ダイアログの「キャンセル」ボタンで閉じる。
  // close() からも呼ばれるため hasReanalyzeConfirmTarget でガードする。
  // 【修正①: event 引数を追加】
  closeReanalyzeConfirm(event) {
    if (this.hasReanalyzeConfirmTarget) {
      this.reanalyzeConfirmTarget.setAttribute("hidden", "")
    }
  }

  // ============================================================
  // dismissTask(event)
  // ============================================================
  //
  // タスク提案の「この提案を除外する」ボタンをクリックしたとき
  // その提案カードを DOM から完全に削除する。
  //
  // 【修正④: display:none → remove() に変更】
  //   変更前: card.style.display = 'none'
  //     問題1: display:none でも checkbox が送信される可能性がある
  //     問題2: Turbo キャッシュ復元時に非表示が解除されて復活する
  //     問題3: スクリーンリーダーに hidden でない要素として認識される
  //   変更後: checkbox.disabled = true にしてから card.remove() で DOM から削除する。
  //     checkbox.disabled: フォーム送信時に値が送られない（確実に除外）
  //     card.remove(): DOM から完全削除（Turbo 復元でも戻らない）
  //
  // 【data-task-card 属性（修正③）】
  //   変更前: button.closest('.border.border-gray-200.rounded-xl.overflow-hidden')
  //     Tailwind クラス名が変わると壊れる脆い実装。
  //   変更後: button.closest('[data-task-card]')
  //     data 属性で識別するため CSS クラス変更の影響を受けない。
  dismissTask(event) {
    const button = event.currentTarget
    const idx = button.dataset.taskIdx

    // チェックボックスを disabled にしてフォーム送信から除外する
    const checkbox = this.element.querySelector(`#modal_task_${idx}`)
    if (checkbox) {
      checkbox.checked = false
      checkbox.disabled = true  // disabled: true でフォーム送信時に値が送られない
    }

    // 提案カードを DOM から完全削除する（data-task-card 属性で識別）
    const card = button.closest("[data-task-card]")
    if (card) {
      card.remove()  // remove() で DOM から完全削除（display:none より確実）
    }
  }
}