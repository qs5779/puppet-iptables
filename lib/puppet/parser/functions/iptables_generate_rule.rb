module Puppet::Parser::Functions
  newfunction(:iptables_generate_rule, :type => :rvalue, :doc => <<-EOS
Provided an array of options, generates iptables rule(s).
EOS
) do |args|
    Puppet::Parser::Functions.function('iptables_parse_options')
    Puppet::Parser::Functions.function('format_action')
    Puppet::Parser::Functions.function('split_ip_by_version')
    Puppet::Parser::Functions.function('format_chain')
    Puppet::Parser::Functions.function('format_interface')
    Puppet::Parser::Functions.function('format_port')
    Puppet::Parser::Functions.function('format_protocol')
    Puppet::Parser::Functions.function('format_state')

    opt = args[0]

    version = '4'
    version = String(args[1])[-1].chr \
      if String(args[1]) =~ /(?i-mx:(ip)?(v)?(4|6))/

    raise Puppet::Error, "invalid version detected - #{version}" \
      unless version =~ /(4|6)/

    flg = { }
    flg = opt['mod_flags'] if opt['mod_flags'].is_a?(Hash)
    flg.default=false

    # addresses are arrays that should always have at least one object, even if
    # its an empty-string
    dst = function_split_ip_by_version( [ opt['destination'] ] )[version]
    dst.push('') if dst.size == 0
    src = function_split_ip_by_version( [ opt['source'] ] )[version]
    src.push('') if src.size == 0

    # our ports also require a little logic
    dpt_h = function_format_port( [ opt['destination_port'], 'dport' ] )
    dpt = dpt_h['port']
    spt_h = function_format_port( [ opt['source_port'], 'sport' ] )
    spt = spt_h['port']
    flg['multiport'] = true if spt_h['multiport'] or dpt_h['multiport']

    # the rest are pretty easy
    act = function_format_action( [ opt['action'] ] )
    chn = function_format_chain( [ opt['chain'] ] )
    in_int = function_format_interface( [ opt['incoming_interface'], 'in' ] )
    out_int = function_format_interface( [ opt['outgoing_interface'], 'out' ] )
    proto = function_format_protocol( [ opt['protocol'], version ] )
    ste = function_format_state( [ opt['state'] ] )

    # logging options are all formatted in one function, so we'll pass in a
    # hash of values.  we'll also only format if the act_LOG flag is set,
    # otherwise these options are useless
    log_opts = {
      'log_ip_opt' => opt['log_ip_opt'],
      'log_level' => opt['log_level'],
      'log_prefix' => opt['log_prefix'],
      'log_tcp_opt' => opt['log_tcp_opt'],
      'log_tcp_sequence' => opt['log_tcp_sequence'],
    }
    log = function_format_log( [ log_opts ] ) if flg['act_LOG']

    # throw some errors when appropriate
    raise Puppet::ParseError,
      "only the FORWARD chain may specify both an in and out interface" \
      + " FWD=#{flg['chn_FORWARD']}, out=#{out_int}, in=#{in_int}" \
      if out_int != '' and in_int != '' and ! flg['chn_FORWARD']

    raise Puppet::Error,
      "something broke. we should have a valid CHAIN by this point" \
      if chn == ''

    #
    ## begin processing
    #
    rules = [ ]

    # lets handle the comments first
    comment_line_width = 80
    comment = opt['comment']
    if comment != nil 
      prepend = "# "
      comment_width = comment_line_width - prepend.length
      comments = []
      if comment.kind_of?(Array)
        comment.each do |c|
          comments += c.scan(/.{1,#{comment_width}}/) if c.kind_of?(String)
        end
      else
        comments = comment.scan(/.{1,#{comment_width}}/)
      end
      comments.map! { |c| c = prepend + c }
      rules += comments
    end

    # allow users to pass rule rule code through, without being
    # tampered with
    raw = opt['raw']

    src.each do |s|
      # we'll store our pieces here, and join() them later
      rule = []

      @src = "-s #{s}" if s != ''
      @src = nil if s == nil or s == ''
      dst.each do |d|
        @dst = "-d #{d}" if d != ''
        @dst = nil if d == nil or d == ''
        rule.push(chn)
        rule.push(in_int)
        rule.push(out_int)
        rule.push(@src)
        rule.push(@dst)
        rule.push(proto)
        rule.push('-m multiport') if flg['multiport']
        rule.push(spt)
        rule.push(dpt)
        rule.push(ste)
        rule.push(raw)
        rule.push(act)
        rule.push(log) if flg['act_LOG']
        rule.compact!
        rule.delete('')
      end

      rules.push(rule.join(' '))
    end
    return rules
  end
end