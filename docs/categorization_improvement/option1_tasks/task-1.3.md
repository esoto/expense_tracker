### Task 1.3: Pattern Cache Service
**Priority**: High  
**Estimated Hours**: 3  
**Dependencies**: Task 1.2  

#### Description
Implement efficient caching layer for pattern lookups with Redis and memory store.

#### Acceptance Criteria
- [ ] Two-tier cache (memory + Redis) implemented
- [ ] Automatic cache warming on startup
- [ ] Cache invalidation on pattern updates
- [ ] Performance: < 1ms for cache hits
- [ ] Monitoring for cache hit rates
- [ ] Configurable TTL values

#### Technical Implementation
```ruby
# app/services/categorization/pattern_cache.rb
class Categorization::PatternCache
  include Singleton
  
  def initialize
    @memory_store = ActiveSupport::Cache::MemoryStore.new(
      size: 50.megabytes,
      expires_in: 5.minutes
    )
    @redis = Redis::Namespace.new('patterns', redis: Redis.current)
    warm_cache
  end
  
  def fetch_patterns(bank_name = nil)
    cache_key = "patterns:#{bank_name || 'all'}:#{Date.current}"
    
    # Try memory first
    @memory_store.fetch(cache_key) do
      # Then Redis
      redis_data = @redis.get(cache_key)
      return JSON.parse(redis_data) if redis_data
      
      # Finally database
      patterns = load_patterns_from_db(bank_name)
      
      # Store in both caches
      @redis.setex(cache_key, 24.hours.to_i, patterns.to_json)
      patterns
    end
  end
  
  def invalidate(pattern_id = nil)
    if pattern_id
      # Selective invalidation
      @memory_store.delete_matched("patterns:*")
      @redis.del(@redis.keys("patterns:*"))
    else
      # Full invalidation
      @memory_store.clear
      @redis.flushdb
    end
  end
  
  private
  
  def warm_cache
    Rails.logger.info "Warming pattern cache..."
    fetch_patterns # Load all patterns
    Rails.logger.info "Pattern cache warmed with #{@memory_store.stats[:entries]} entries"
  end
end
```
