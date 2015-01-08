#!/usr/bin/env ruby
#
# Check Disk Plugin
# ===
#
# Uses GNU's -T option for listing filesystem type; unfortunately, this
# is not portable to BSD. Warning/critical levels are percentages only.
#
# Copyright 2011 Sonian, Inc <chefs@sonian.net>
# Heavily modified by Miika Kankare - Cybercom Finland Oy - 2015
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'

class CheckDisk < Sensu::Plugin::Check::CLI

  option :fstype,
    :short => '-t TYPE[,TYPE]',
    :description => 'Only check fs type(s)',
    :proc => proc {|a| a.split(',') }

  option :ignoretype,
    :short => '-x TYPE[,TYPE]',
    :description => 'Ignore fs type(s)',
    :proc => proc {|a| a.split(',') }

  option :ignoremnt,
    :short => '-i MNT[,MNT]',
    :description => 'Ignore mount point(s)',
    :proc => proc {|a| a.split(',') }

  option :remotefs,
    :short => '-r',
    :description => 'Include remote filesystems in df',
    :boolean => true

  option :ignoreline,
    :short => '-l PATTERN[,PATTERN]',
    :description => 'Ignore df line(s) matching pattern(s)',
    :proc => proc { |a| a.split(',') }

  option :includeline,
    :short => '-L PATTERN[,PATTERN]',
    :description => 'Only include df line(s) matching pattern(s)',
    :proc => proc { |a| a.split(',') }

  option :warn,
    :short => '-w PERCENT',
    :description => 'Warn if PERCENT or more of disk full',
    :proc => proc {|a| a.to_i }

  option :crit,
    :short => '-c PERCENT',
    :description => 'Critical if PERCENT or more of disk full',
    :proc => proc {|a| a.to_i }

  option :iwarn,
    :short => '-W PERCENT',
    :description => 'Warn if PERCENT or more of inodes used',
    :proc => proc {|a| a.to_i }

  option :icrit,
    :short => '-K PERCENT',
    :description => 'Critical if PERCENT or more of inodes used',
    :proc => proc {|a| a.to_i }

  option :debug,
      :short => '-d',
      :long => '--debug',
      :description => 'Output list of included filesystems'

  def initialize
    super
    @crit_fs = []
    @warn_fs = []
    @ok_fs = []
    @mnts = []
  end

  def read_df
    if config[:remotefs]
      df_params = "-PT"
    else
      df_params = "-lPT"
    end

    if config[:warn] || config[:crit]
      `df #{df_params}`.split("\n").drop(1).each do |line|
        begin
          _fs, type, _blocks, _used, _avail, capacity, mnt = line.split
          next if config[:includeline] && !config[:includeline].find { |x| line.match(x) }
          next if config[:fstype] && !config[:fstype].include?(type)
          next if config[:ignoretype] && config[:ignoretype].include?(type)
          next if config[:ignoremnt] && config[:ignoremnt].include?(mnt)
          next if config[:ignoreline] && config[:ignoreline].find { |x| line.match(x) }
          puts line if config[:debug]
        rescue
          unknown "Malformed line from df: #{line}"
        end

        @mnts << "#{mnt}" unless @mnts.include?(mnt)
        if config[:crit] && capacity.to_i >= config[:crit]
          @crit_fs << "#{mnt} #{capacity} > #{config[:crit]}%"
        elsif config[:warn] && capacity.to_i >= config[:warn]
          @warn_fs <<  "#{mnt} #{capacity} > #{config[:warn]}%"
        end
      end
    end

    df_params = df_params + "i"
    if config[:iwarn] || config[:icrit]
      `df #{df_params}`.split("\n").drop(1).each do |line|
        begin
          _fs, type, _inodes, _used, _avail, capacity, mnt = line.split
          next if config[:includeline] && !config[:includeline].find { |x| line.match(x) }
          next if config[:fstype] && !config[:fstype].include?(type)
          next if config[:ignoretype] && config[:ignoretype].include?(type)
          next if config[:ignoremnt] && config[:ignoremnt].include?(mnt)
          next if config[:ignoreline] && config[:ignoreline].find { |x| line.match(x) }
          puts line if config[:debug]
        rescue
          unknown "Malformed line from df: #{line}"
        end

        @mnts << "#{mnt}" unless @mnts.include?(mnt)
        if config[:icrit] && capacity.to_i >= config[:icrit]
          @crit_fs << "#{mnt} inodes #{capacity} > #{config[:icrit]}%"
        elsif config[:iwarn] && capacity.to_i >= config[:iwarn]
          @warn_fs << "#{mnt} inodes #{capacity} > #{config[:iwarn]}%"
        end
      end
    end
  end

  def disk_usage
    # Something is over the limits
    if !@crit_fs.empty? || !@warn_fs.empty?
      msg = (@crit_fs + @warn_fs).join(', ')
    else
      msg = @mnts.join(", ")

      if config[:warn]
        msg << " < #{config[:warn]}%"
      elsif config[:crit]
        msg << " < #{config[:crit]}%"
      end

      if config[:iwarn]
        msg << " and" unless !msg.include?("<")
        msg << " inodes < #{config[:iwarn]}%"
      elsif config[:icrit]
        msg << " and" unless !msg.include?("<")
        msg << " inodes < #{config[:icrit]}%"
      end
    end

    msg
  end

  def run
    if config[:includeline] && config[:ignoreline]
      unknown 'Do not use -l and -L options concurrently'
    end

    if !config[:crit] && \
       !config[:icrit] && \
       !config[:warn] && \
       !config[:iwarn]
      unknown 'Warning or critical levels not defined'
    end

    # Read disk usage
    read_df

    unknown 'No filesystems found' unless @mnts.length > 0

    if config[:crit] || config[:icrit]
      critical disk_usage unless @crit_fs.empty?
    end
    if config[:warn] || config[:iwarn]
      warning disk_usage unless @warn_fs.empty?
    end

    ok disk_usage
  end

end
