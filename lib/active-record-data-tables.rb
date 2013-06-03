class ActiveRecordDataTables
  def initialize(args)
    @args = args
    @params = @args[:params]
    @columns = @args[:columns]
  end
  
  def execute
    @obj = @args[:model]
    sorting
    limit
  end
  
  private
  
  def limit
    disp_start = @params["iDisplayStart"].to_i
    disp_length = @params["iDisplayLength"].to_i
  end
  
  def sorting
    sort_no = 0
    sorts = []
    
    loop do
      name_col = "iSortCol_#{sort_no}"
      name_mode = "sSortDir_#{sort_no}"
      sort_col = @params[name]
      break if !sort_col
      
      col_name = @columns[name_col]
      next if !col_name
      
      if name_mode == "desc"
        sort_mode = "DESC"
      else
        sort_mode = "ASC"
      end
      
      sorts << "`#{escape_col(col_name)}` #{sort_mode}"
      
      sort_no += 1
    end
    
    @obj = @obj.order(sorts.join(" "))
  end
  
  def escape_col(name)
    raise "Possible SQL injection hack: '#{name}'." unless name.to_s.match(/\A[A-z\d_+]\Z/)
    return name
  end
end