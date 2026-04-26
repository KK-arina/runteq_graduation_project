# db/cable_migrate/20260426000001_create_solid_cable_messages.rb
#
# ==============================================================================
# solid_cable_messages テーブルのマイグレーション
# ==============================================================================
#
# 【このファイルの役割】
#   solid_cable が Action Cable のメッセージを保存するためのテーブルを作成する。
#   GoodJob が broadcast_replace_to を呼ぶと、このテーブルにメッセージが書き込まれ、
#   ブラウザ側の solid_cable がポーリングして読み取り、Turbo Stream を更新する。
#
# 【カラムの説明】
#   channel  : Action Cable のチャンネル名（例: "user_purpose_27"）
#   payload  : 送信するメッセージの内容（Turbo Stream の HTML）
#   created_at: メッセージの作成日時（message_retention による削除に使用）
# ==============================================================================

class CreateSolidCableMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :solid_cable_messages do |t|
      # channel: どのチャンネル宛のメッセージかを識別する文字列
      # null: false で必須。インデックスで高速検索できるようにする。
      t.text :channel, null: false

      # payload: メッセージの本文（Turbo Stream の HTML など）
      # text 型で長い HTML も格納できるようにする。
      t.text :payload, null: false

      # created_at: メッセージの作成日時
      # message_retention（1.day）による古いメッセージの削除に使用する。
      t.datetime :created_at, null: false
    end

    # channel のインデックス: チャンネル名でメッセージを素早く検索するため
    add_index :solid_cable_messages, :channel

    # created_at のインデックス: 古いメッセージを削除するための検索に使用
    add_index :solid_cable_messages, :created_at
  end
end