class AddHealthMetricsToExternalServices < ActiveRecord::Migration[8.1]
  def change
    add_column :arr_apps, :last_http_status, :integer
    add_column :arr_apps, :last_duration_ms, :integer
    add_column :indexers, :last_http_status, :integer
    add_column :indexers, :last_duration_ms, :integer
  end
end
