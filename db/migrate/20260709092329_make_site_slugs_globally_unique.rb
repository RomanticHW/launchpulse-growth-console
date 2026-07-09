class MakeSiteSlugsGloballyUnique < ActiveRecord::Migration[8.1]
  def up
    duplicates = select_all(<<~SQL.squish).to_a
      SELECT slug, COUNT(*) AS c FROM sites GROUP BY slug HAVING COUNT(*) > 1
    SQL
    raise "Duplicate site slugs exist: #{duplicates.inspect}" if duplicates.any?

    if index_exists?(:sites, %i[account_id slug], name: "index_sites_on_account_id_and_slug")
      remove_index :sites, name: "index_sites_on_account_id_and_slug"
    end
    add_index :sites, :slug, unique: true, name: "index_sites_on_slug"
  end

  def down
    remove_index :sites, name: "index_sites_on_slug" if index_exists?(:sites, :slug, name: "index_sites_on_slug")
    add_index :sites, %i[account_id slug], unique: true, name: "index_sites_on_account_id_and_slug"
  end
end
