// Stimulus コントローラー: habit_checkbox
// チェックボックスの変更を検知し、フォームを自動送信する
//
// Turbo Frame と組み合わせることで:
// - フォーム送信後はTurbo Frameが自動的に該当部分だけ置き換える
// - Turbo Streamよりシンプルで確実な動作

import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="habit-checkbox"
export default class extends Controller {
  static targets = ["form", "loading"]

  connect() {
    console.log("Habit checkbox controller connected")
  }

  submit(event) {
    event.preventDefault()

    // チェックボックスをdisabledにして連打防止
    // Turbo Frameで要素が置き換わると自動的にdisabledが解除される
    const checkbox = event.target
    checkbox.disabled = true

    console.log("Submitting habit record...")

    // 「保存中...」を表示
    this.loadingTarget.classList.remove("hidden")

    // 即座にフォームを送信
    this.formTarget.requestSubmit()

    // エラーハンドリング（タイムアウト3秒）
    setTimeout(() => {
      checkbox.disabled = false
      if (this.hasLoadingTarget) {
        this.loadingTarget.classList.add("hidden")
      }
    }, 3000)
  }
}