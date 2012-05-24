module CounterCulture

  module ActiveRecord

    def self.included(base)
      # also add class methods to ActiveRecord::Base
      base.extend ClassMethods
    end

    module ClassMethods
      # this holds all configuration data
      attr_reader :after_commit_counter_cache

      # called to configure counter caches
      def counter_cache(relation, options = {})
        unless @after_commit_counter_cache
          # initialize callbacks only once
          after_create :_update_counts_after_create
          after_destroy :_update_counts_after_destroy
          after_update :_update_counts_after_update
        end

        # we keep a list of all counter caches we must maintain
        @after_commit_counter_cache ||= [] 

        # add the current information to our list
        @after_commit_counter_cache<< {
          :relation => relation,
          :counter_cache_name => (options[:column_name] || "#{name.tableize}_count"),
          :foreign_key_values => options[:foreign_key_values]
        }
      end
    end

    private
    # called by after_create callback
    def _update_counts_after_create
      self.class.after_commit_counter_cache.each do |hash|
        # increment counter cache
        change_counter_cache(true, hash)
      end
    end

    # called by after_destroy callback
    def _update_counts_after_destroy
      self.class.after_commit_counter_cache.each do |hash|
        # decrement counter cache
        change_counter_cache(false, hash)
      end
    end

    # called by after_update callback
    def _update_counts_after_update
      self.class.after_commit_counter_cache.each do |hash|
        # only update counter caches if the foreign key changed
        if send("#{first_level_relation_foreign_key(hash[:relation])}_changed?")
          # increment the counter cache of the new value
          change_counter_cache(true, hash)
          # decrement the counter cache of the old value
          change_counter_cache(false, hash, true)
        end
      end
    end

    # increments or decrements a counter cache
    #
    # increment: true to increment, false to decrement
    # hash:
    #   :relation => which relation to increment the count on, 
    #   :counter_cache_name => the column name of the counter cache
    # was: whether to get the current value or the old value of the
    #   first part of the relation
    def change_counter_cache(increment, hash, was = false)
      # default to the current foreign key value
      id_to_change = foreign_key_value(hash[:relation], was)
      # allow overwriting of foreign key value by the caller
      id_to_change = hash[:foreign_key_values].call(id_to_change) if hash[:foreign_key_values]
      if id_to_change
        execute_after_commit do
          # increment or decrement?
          method = increment ? :increment_counter : :decrement_counter

          # figure out what the column name is
          if hash[:counter_cache_name].is_a? Proc
            # dynamic column name -- call the Proc
            counter_cache_name = hash[:counter_cache_name].call(self) 
          else
            # static column name
            counter_cache_name = hash[:counter_cache_name]
          end

          # do it!
          relation_klass(hash[:relation]).send(method, counter_cache_name, id_to_change)
        end
      end
    end

    # gets the value of the foreign key on the given relation
    #
    # relation: a symbol or array of symbols; specifies the relation
    #   that has the counter cache column
    # was: whether to get the current or past value from ActiveRecord;
    #   pass true to get the past value, false or nothing to get the
    #   current value
    def foreign_key_value(relation, was = false)
      relation = relation.is_a?(Enumerable) ? relation.dup : [relation]
      if was
        first = relation.shift
        foreign_key_value = send("#{relation_foreign_key(first)}_was")
        value = relation_klass(first).find(foreign_key_value) if foreign_key_value
      else
        value = self
      end
      while !value.nil? && relation.size > 0
        value = value.send(relation.shift)
      end
      return value.try(:id)
    end

    # gets the reflect object on the given relation
    #
    # relation: a symbol or array of symbols; specifies the relation
    #   that has the counter cache column
    def relation_reflect(relation)
      relation = relation.is_a?(Enumerable) ? relation.dup : [relation]

      # go from one relation to the next until we hit the last reflect object
      klass = self.class
      while relation.size > 0
        cur_relation = relation.shift
        reflect = klass.reflect_on_association(cur_relation)
        raise "No relation #{cur_relation} on #{klass.name}" if reflect.nil?
        klass = reflect.klass
      end

      return reflect
    end

    # gets the class of the given relation
    #
    # relation: a symbol or array of symbols; specifies the relation
    #   that has the counter cache column
    def relation_klass(relation)
      relation_reflect(relation).klass
    end

    # gets the foreign key name of the given relation
    #
    # relation: a symbol or array of symbols; specifies the relation
    #   that has the counter cache column
    def relation_foreign_key(relation)
      relation_reflect(relation).foreign_key
    end
    
    # gets the foreign key name of the relation. will look at the first
    # level only -- i.e., if passed an array will consider only its
    # first element
    #
    # relation: a symbol or array of symbols; specifies the relation
    #   that has the counter cache column
    def first_level_relation_foreign_key(relation)
      relation = relation.first if relation.is_a?(Enumerable)
      relation_reflect(relation).foreign_key
    end
  end

  # extend ActiveRecord with our own code here
  ::ActiveRecord::Base.send :include, ActiveRecord
end