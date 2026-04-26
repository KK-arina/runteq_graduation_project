# db/migrate/XXXXXX_add_channel_hash_to_solid_cable_messages.rb
#
# ==============================================================================
# solid_cable_messages テーブルに channel_hash カラムを追加するマイグレーション
# ==============================================================================
#
# 【追加理由】
#   solid_cable 3.0.12 は channel_hash カラムを使って
#   チャンネル名のハッシュ値でメッセージを検索する。
#   既存の solid_cable_messages テーブルにはこのカラムが存在しないため
#   ActiveModel::UnknownAttributeError が発生していた。
#
# 【channel_hash の役割】
#   channel（テキスト）をそのまま比較するより、
#   ハッシュ値（整数）で比較する方が DB の検索が高速になる。
#   solid_cable が内部的にチャンネルを特定するために使用する。
# ==============================================================================

class AddChannelHashToSolidCableMessages < ActiveRecord::Migration[7.2]
  def change
    # channel_hash: channel のハッシュ値を格納する bigint カラム
    # null: false で必須。既存レコードのデフォルト値は 0 にする。
    add_column :solid_cable_messages, :channel_hash, :bigint,
               null: false, default: 0

    # channel_hash のインデックス: チャンネルの高速検索に使用する
    add_index :solid_cable_messages, :channel_hash

    # 既存レコードの channel_hash を計算して更新する
    # Zlib::crc32 で channel 文字列のハッシュ値を生成する
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE solid_cable_messages
          SET channel_hash = hashtext(channel)
        SQL
      end
    end
  end
end