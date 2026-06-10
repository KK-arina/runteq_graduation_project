// app/javascript/controllers/settings_profile_controller.js
//
// ==============================================================================
// SettingsProfileController（G-6 新規作成）
// ==============================================================================
//
// 【このコントローラーの役割】
//   設定ページ（20番）のプロフィール編集インライン機能を制御する。
//   「編集」ボタンをクリックするとフォームを表示（20-2番状態）し、
//   他のセクションを視覚的に非活性化（薄く・クリック不可）にする。
//
// 【20-2番の状態とは】
//   UI設計図の「20-2番（プロフィール編集中）」:
//     - プロフィール編集フォームが展開されている
//     - 他のセクションが非活性化されている（薄く・クリック不可）
//     - 「保存」または「キャンセル」で元の状態に戻る
//
// 【static targets を使う理由】
//   HTML 側で data-settings-profile-target="xxx" を付けた要素を
//   JavaScript から this.xxxTarget で参照できるようにする Stimulus の仕組み。
//   getElementById より Stimulus らしく、HTML との対応が明確になる。
//
// 【HTML 側の使い方】
//   <div data-controller="settings-profile">
//     <!-- プロフィールセクション -->
//     <button data-action="click->settings-profile#openEdit"
//             data-settings-profile-target="editButton">編集</button>
//     <div data-settings-profile-target="display">表示モード</div>
//     <div data-settings-profile-target="form" hidden>編集フォーム</div>
//     <!-- 他のセクション（編集中に非活性化される） -->
//     <section data-settings-profile-target="otherSection">通知設定等</section>
//   </div>
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // static targets: このコントローラーが参照する HTML 要素の宣言
  // ============================================================
  //
  // 各ターゲットの役割:
  //   display:      プロフィールの「表示モード」（名前・メール等の dl 要素）
  //   form:         プロフィールの「編集フォーム」（hidden で表示/非表示を切り替える）
  //   editButton:   「編集」ボタン（編集中は非表示にして二重フォーム展開を防ぐ）
  //   otherSection: プロフィール以外のセクション（編集中は薄くしてクリック不可にする）
  static targets = ["display", "form", "editButton", "otherSection"]

  // ============================================================
  // openEdit(): 編集モードを開く（「編集」ボタンクリック時）
  // ============================================================
  //
  // 【処理の流れ】
  //   1. 「表示モード」を非表示にする（hidden 属性を付ける）
  //   2. 「編集フォーム」を表示する（hidden 属性を取り除く）
  //   3. 「編集」ボタンを非表示にする（二重展開防止）
  //   4. 他のセクションを非活性化する（opacity-50 + pointer-events-none）
  //   5. フォームの入力フィールドにフォーカスを当てる（UX向上）
  openEdit() {
    // 1. 表示モードを非表示にする
    //    setAttribute("hidden", "") で display:none が適用される
    if (this.hasDisplayTarget) {
      this.displayTarget.setAttribute("hidden", "")
    }

    // 2. 編集フォームを表示する
    //    removeAttribute("hidden") で表示状態になる
    if (this.hasFormTarget) {
      this.formTarget.removeAttribute("hidden")

      // 5. フォームの最初のテキスト入力にフォーカスを当てる
      //    setTimeout(0) を使う理由:
      //      hidden 属性の削除直後は DOM の描画が完了していない場合がある。
      //      setTimeout(0) でブラウザの描画サイクルの後にフォーカスを当てることで
      //      確実にフォーカスが当たる。
      setTimeout(() => {
        const firstInput = this.formTarget.querySelector(
          "input[type='text'], input:not([type='hidden'])"
        )
        if (firstInput) firstInput.focus()
      }, 0)
    }

    // 3. 「編集」ボタンを非表示にする
    //    フォームが開いているときに「編集」ボタンが見えていると
    //    二重にフォームを展開しようとする誤操作を誘発するため非表示にする
    if (this.hasEditButtonTarget) {
      this.editButtonTarget.setAttribute("hidden", "")
    }

    // 4. 他のセクションを非活性化する
    //    otherSectionTargets は配列なので forEach で全て処理する
    this.otherSectionTargets.forEach(section => {
      // opacity-50: 半透明にして「操作できない」ことを視覚的に示す
      //   Tailwind CSS のクラス。要素の透明度を 50% にする。
      section.classList.add("opacity-50")

      // pointer-events-none: マウスクリック・タップを無効にする
      //   Tailwind CSS のクラス。CSS の pointer-events: none に対応。
      //   これにより他のセクションのボタン・リンクが操作できなくなる。
      section.classList.add("pointer-events-none")

      // select-none: テキスト選択を無効にする
      //   「使えない状態」をより明確に表現するため追加する。
      section.classList.add("select-none")
    })
  }

  // ============================================================
  // closeEdit(): 編集モードを閉じる（「キャンセル」ボタンクリック時）
  // ============================================================
  //
  // 【処理の流れ】
  //   1. 「編集フォーム」を非表示にする
  //   2. 「表示モード」を表示する
  //   3. 「編集」ボタンを表示する
  //   4. 他のセクションの非活性化を解除する
  closeEdit() {
    // 1. 編集フォームを非表示にする
    if (this.hasFormTarget) {
      this.formTarget.setAttribute("hidden", "")
    }

    // 2. 表示モードを表示する
    if (this.hasDisplayTarget) {
      this.displayTarget.removeAttribute("hidden")
    }

    // 3. 「編集」ボタンを表示する
    if (this.hasEditButtonTarget) {
      this.editButtonTarget.removeAttribute("hidden")
    }

    // 4. 他のセクションの非活性化を解除する
    //    openEdit() で追加したクラスを全て削除する
    this.otherSectionTargets.forEach(section => {
      section.classList.remove("opacity-50")
      section.classList.remove("pointer-events-none")
      section.classList.remove("select-none")
    })
  }

  // ============================================================
  // disconnect(): コントローラーが DOM から切り離されたとき自動で呼ばれる
  // ============================================================
  //
  // 【なぜ必要か】
  //   Turbo Drive でページ遷移したとき、編集モードのまま遷移すると
  //   pointer-events-none 等のクラスが次のページにも残ってしまう場合がある。
  //   disconnect() でクリアすることでスタイルの残留を防ぐ。
  disconnect() {
    this.otherSectionTargets.forEach(section => {
      section.classList.remove("opacity-50", "pointer-events-none", "select-none")
    })
  }
}