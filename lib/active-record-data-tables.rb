require "string-cases"

class ActiveRecordDataTables
  def initialize(args)
    @args = args
    @params = @args[:params]
    @filter_params = @args[:filter_params]
    @force_filter_for = @args[:force_filter_for]
    @dts = @params[:dataTables]
    @columns = @args[:columns]

    @model = @args[:model]
    raise "No ':model' was given." unless @model
    @model_method_name = StringCases.camel_to_snake(@model.name)

    @joins = {}
    @sort_columns = [:title, :name]
    @executed = false
  end

  def execute(args = {})
    @executed = true
    @query = args[:search] || @model

    filter unless args[:skip_filter]
    sorting
    limit

    return @query
  end

  def json(final_query = nil)
    unless final_query
      execute unless @executed
      final_query = @query
    end

    dis_rec_count = final_query.limit(nil).count
    dis_rec_count = dis_rec_count.length if dis_rec_count.is_a?(Hash)

    res = {
      :sEcho => @dts[:sEcho] ? @dts[:sEcho].to_i : 1,
      :iTotalRecords => @model.count,
      :iTotalDisplayRecords => dis_rec_count,
      :aaData => []
    }
  end

  private

  # Checks the given parameters for filters and manipulates the query based on it.
  def filter
    @filter_params.each do |key, val|
      # Strip empty values from the array if the given value is an array.
      val.select!{ |val| !val.to_s.empty? } if val.is_a?(Array)

      # Convert key if it starts with a column name.
      key = key.slice(@model_method_name.length + 1, key.length) if key.start_with?("#{@model_method_name}_")

      if @force_filter_for && @force_filter_for.include?(key)
        ret = @args[:filter].call(:key => key, :val => val, :query => @query)
        @query = ret if ret
      elsif @model.column_names.include?(key)
        if val.is_a?(Array) && val.empty?
          # Ignore.
        else
          @query = @query.where(key => val)
        end
      elsif match = key.to_s.match(/^(.+)_like$/) and @model.column_names.include?(match[1])
        next if val.blank?
        table = @model.arel_table
        
        val.to_s.strip.split(/\s+/).each do |str|
          @query = @query.where(table[match[1].to_sym].matches("%#{escape(str)}%"))
        end
      elsif @args[:filter]
        ret = @args[:filter].call(:key => key, :val => val, :query => @query)
        @query = ret if ret
      else
        raise "Dont know what to do regarding filter with key: '#{key}'."
      end
    end
  end

  # Checks the given parameters for limits and manipulates the query based on it.
  def limit
    raise "'iDisplayStart' was not given? #{@dts}" unless @dts.key?("iDisplayStart")
    raise "'iDisplayEnd' was not given? #{@dts}" unless @dts.key?("iDisplayLength")

    disp_start = @dts["iDisplayStart"].to_i
    disp_length = @dts["iDisplayLength"].to_i

    @query = @query.page((disp_start / disp_length) + 1).per(disp_length)
  end

  # Checks the given parameters for sorting and manipulates the query based on it.
  def sorting
    sort_no = 0
    sorts = []

    loop do
      sorted = false
      name_col = "iSortCol_#{sort_no}"
      name_mode = "sSortDir_#{sort_no}"
      sort_col = @dts[name_col]
      break if !sort_col

      col_name = @columns[sort_col.to_i]
      next if !col_name

      if @dts[name_mode] == "desc"
        sort_mode = "DESC"
      else
        sort_mode = "ASC"
      end

      if match = col_name.to_s.match(/^(.+)_id$/)
        method_name = match[1]
        sub_model_name = StringCases.snake_to_camel(col_name.slice(0, col_name.length - 3))

        if Kernel.const_defined?(sub_model_name)
          sub_model_const = Kernel.const_get(sub_model_name)
          unless @joins.key?(method_name)
            @query = @query.includes(method_name)
            @joins[method_name] = true
          end

          @sort_columns.each do |sort_col_name|
            if sub_model_const.column_names.include?(sort_col_name.to_s)
              sorts << "`#{sub_model_const.table_name}`.`#{escape_col(sort_col_name)}` #{sort_mode}"
              sorted = true
              break
            end
          end
        end
      end

      if @model.column_names.include?(col_name.to_s)
        sorts << "`#{@model.table_name}`.`#{escape_col(col_name)}` #{sort_mode}"
      elsif @args[:sort]
        res = @args[:sort].call(:key => col_name, :sort_mode => sort_mode, :query => @query)
        @query = res if res
      else
        raise "Unknown sort-column: '#{col_name}'."
      end

      sort_no += 1
    end

    @query = @query.order(sorts.join(", "))
  end

  # Escapes the given string to be used in a SQL statement.
  def escape(str)
    return ActiveRecord::Base.connection.quote_string(str)
  end

  # Escapes the given name as a column and checks for SQL-injections.
  def escape_col(name)
    raise "Possible SQL injection hack: '#{name}'." unless name.to_s.match(/\A[A-z\d_]+\Z/)
    return name
  end
end