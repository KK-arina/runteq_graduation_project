// app/javascript/controllers/dismissible_controller.js
//
// ==============================================================================
// DismissibleController（G-7 追加）
// ==============================================================================
//
// 【このファイルの役割】
//   バナーや通知パネルを「×ボタン」で非表示にする汎用 Stimulus コントローラー。
//   G-7 のダッシュボード PMVV 完了バナーで使用する。
//
// 【_pmvv_completion_banner.html.erb との関係】
//   このコントローラーは「内側のバナー本体 div」に付けることで、
//   外側の id="dashboard_pmvv_completion_banner" div を hidden にせず保護する設計になっている。
//   この設計により、×で閉じた後も Turbo Stream が次回のブロードキャスト先を
//   正しく発見でき、再通知が機能し続ける。
//
// 【なぜ新しいコントローラーを作るのか】
//   既存の flash_controller.js は「タイムアウトで自動非表示」する機能を持ち、
//   フラッシュメッセージ専用の設計になっている。
//   Turbo Stream で差し替えられるバナーに使うと自動タイムアウトが
//   邪魔になる可能性があるため、シンプルな「手動で閉じるだけ」の
//   コントローラーを別途作成する。
//
// 【汎用設計にする理由】
//   今後、別の「×で閉じられるバナー」が追加されたときにも
//   このコントローラーをそのまま再利用できる。
//
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // connect(): Stimulus がこの要素に接続するたびに呼ばれる。
  // Turbo Stream が replace した後も呼ばれるため、
  // hidden クラスを確実に除去してバナーを表示状態にする。
  connect() {
    this.element.classList.remove("hidden")
  }

  hide() {
    this.element.classList.add("hidden")
  }
}