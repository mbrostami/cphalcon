
/*
 +------------------------------------------------------------------------+
 | Phalcon Framework                                                      |
 +------------------------------------------------------------------------+
 | Copyright (c) 2011-2016 Phalcon Team (https://phalconphp.com)          |
 +------------------------------------------------------------------------+
 | This source file is subject to the New BSD License that is bundled     |
 | with this package in the file docs/LICENSE.txt.                        |
 |                                                                        |
 | If you did not receive a copy of the license and are unable to         |
 | obtain it through the world-wide-web, please send an email             |
 | to license@phalconphp.com so we can send you a copy immediately.       |
 +------------------------------------------------------------------------+
 | Authors: Andres Gutierrez <andres@phalconphp.com>                      |
 |          Eduar Carvajal <eduar@phalconphp.com>                         |
 +------------------------------------------------------------------------+
 */

namespace Phalcon\Cache\Backend;

use Phalcon\Cache\Backend;
use Phalcon\Cache\Exception;
use Phalcon\Cache\FrontendInterface;

/**
 * Phalcon\Cache\Backend\Redis
 *
 * Allows to cache output fragments, PHP data or raw data to a redis backend
 *
 * This adapter uses the special redis key "_PHCR" to store all the keys internally used by the adapter
 *
 *<code>
 * use Phalcon\Cache\Backend\Redis;
 * use Phalcon\Cache\Frontend\Data as FrontData;
 *
 * // Cache data for 2 days
 * $frontCache = new FrontData(
 *     [
 *         "lifetime" => 172800,
 *     ]
 * );
 *
 * // Create the Cache setting redis connection options
 * $cache = new Redis(
 *     $frontCache,
 *     [
 *         "host"       => "localhost",
 *         "port"       => 6379,
 *         "auth"       => "foobared",
 *         "persistent" => false,
 *         "index"      => 0,
 *     ]
 * );
 *
 * // Cache arbitrary data
 * $cache->save("my-data", [1, 2, 3, 4, 5]);
 *
 * // Get data
 * $data = $cache->get("my-data");
 *</code>
 */
class Redis extends Backend
{
	protected _redis = null;

	/**
	 * Phalcon\Cache\Backend\Redis constructor
	 *
	 * @param	Phalcon\Cache\FrontendInterface frontend
	 * @param	array options
	 */
	public function __construct(<FrontendInterface> frontend, options = null)
	{
		if typeof options != "array" {
			let options = [];
		}

		if !isset options["host"] {
			let options["host"] = "127.0.0.1";
		}

		if !isset options["port"] {
			let options["port"] = 6379;
		}

		if !isset options["index"] {
			let options["index"] = 0;
		}

		if !isset options["persistent"] {
			let options["persistent"] = false;
		}

		if !isset options["statsKey"] {
			// Disable tracking of cached keys per default
			let options["statsKey"] = false;
		}

		parent::__construct(frontend, options);
	}

	/**
	 * Create internal connection to redis
	 */
	public function _connect()
	{
		var options, redis, persistent, success, host, port, auth, index;

		let options = this->_options;
		let redis = new \Redis();

		if !fetch host, options["host"] || !fetch port, options["port"] || !fetch persistent, options["persistent"] {
			throw new Exception("Unexpected inconsistency in options");
		}

		if persistent {
			let success = redis->pconnect(host, port);
		} else {
			let success = redis->connect(host, port);
		}

		if !success {
			throw new Exception("Could not connect to the Redisd server ".host.":".port);
		}

        /**
        * use prefix on all keys
        **/
        let success = redis->setOption(\Redis::OPT_PREFIX, "_PHCR");

        if !success {
            throw new Exception("Failed to set option to the Redisd server");
        }

		if fetch auth, options["auth"] {
			let success = redis->auth(auth);

			if !success {
				throw new Exception("Failed to authenticate with the Redisd server");
			}
		}

		if fetch index, options["index"] && index > 0 {
			let success = redis->select(index);

			if !success {
				throw new Exception("Redis server selected database failed");
			}
		}

		let this->_redis = redis;
	}

	/**
	 * Returns a cached content
	 */
	public function get(string keyName, int lifetime = null) -> var | null
	{
		var cachedContent;

		if typeof this->_redis != "object" {
			this->_connect();
		}

		let this->_lastKey = this->_prefix . keyName;
		let cachedContent = this->_redis->get(this->_lastKey);

		if cachedContent === false {
			return null;
		}

		if is_numeric(cachedContent) {
			return cachedContent;
		}

		return this->_frontend->afterRetrieve(cachedContent);
	}

	/**
	 * Stores cached content into the file backend and stops the frontend
	 *
	 * @param int|string keyName
	 * @param string content
	 * @param int lifetime
	 * @param boolean stopBuffer
	 */
	public function save(keyName = null, content = null, lifetime = null, boolean stopBuffer = true) -> boolean
	{
		var frontend, cachedContent, preparedContent,
			tmp, tt1, success, options, specialKey;

		if keyName {
			let this->_lastKey = this->_prefix . keyName;
		}

		if !this->_lastKey {
			throw new Exception("The cache must be started first");
		}

		let frontend = this->_frontend;

		/**
		 * Check if a connection is created or make a new one
		 */
		if typeof this->_redis != "object" {
			this->_connect();
		}

		if content === null {
			let cachedContent = frontend->getContent();
		} else {
			let cachedContent = content;
		}

		/**
		 * Prepare the content in the frontend
		 */
		if !is_numeric(cachedContent) {
			let preparedContent = frontend->beforeStore(cachedContent);
		} else {
			let preparedContent = cachedContent;
		}

		if lifetime === null {
			let tmp = this->_lastLifetime;

			if !tmp {
				let tt1 = frontend->getLifetime();
			} else {
				let tt1 = tmp;
			}
		} else {
			let tt1 = lifetime;
		}

		let success = this->_redis->set(this->_lastKey, preparedContent);

		if !success {
			throw new Exception("Failed storing the data in redis");
		}

		this->_redis->settimeout(this->_lastKey, tt1);

		let options = this->_options;

		if !fetch specialKey, options["statsKey"] {
			throw new Exception("Unexpected inconsistency in options");
		}

		if specialKey !== false {
			this->_redis->sAdd(specialKey, this->_lastKey);
		}

		if stopBuffer === true {
			frontend->stop();
		}

		if frontend->isBuffering() === true {
			echo cachedContent;
		}

		let this->_started = false;

		return true;
	}

	/**
	 * Deletes a value from the cache by its key
	 *
	 * @param int|string keyName
	 */
	public function delete(keyName) -> boolean
	{
		var prefixedKey, options, specialKey;

		if typeof this->_redis != "object" {
			this->_connect();
		}

		let prefixedKey = this->_prefix . keyName;
		let options = this->_options;

		if !fetch specialKey, options["statsKey"] {
			throw new Exception("Unexpected inconsistency in options");
		}

		if specialKey !== false {
			this->_redis->sRem(specialKey, prefixedKey);
		}

		/**
		* Delete the key from redis
		*/
		return (bool) this->_redis->delete(prefixedKey);
	}

	/**
	 * Query the existing cached keys
	 *
	 * @param string prefix
	 */
	public function queryKeys(prefix = null) -> array
	{
		var options, keys, specialKey, key, value;

		if typeof this->_redis != "object" {
			this->_connect();
		}

		let options = this->_options;

		if !fetch specialKey, options["statsKey"] {
			throw new Exception("Unexpected inconsistency in options");
		}

		if specialKey === false {
			throw new Exception("Cached keys need to be enabled to use this function (options['statsKey'] = 'specialKey')!");
		}

		/**
		* Get the key from redis
		*/
		let keys = this->_redis->sMembers(specialKey);
		if typeof keys == "array" {
			for key, value in keys {
				if prefix && !starts_with(value, prefix) {
					unset(keys[key]);
				}
			}

			return keys;
		}

		return [];
	}

	/**
	 * Checks if cache exists and it isn't expired
	 *
	 * @param string keyName
	 * @param int lifetime
	 */
	public function exists(keyName = null, lifetime = null) -> boolean
	{

		if keyName {
			let this->_lastKey = this->_prefix . keyName;
		}

		if this->_lastKey {
			if typeof this->_redis != "object" {
				this->_connect();
			}

			return this->_redis->exists(this->_lastKey);
		}

		return false;
	}

	/**
	 * Increment of given $keyName by $value
	 *
	 * @param string keyName
	 * @param int value
	 */
	public function increment(keyName = null, value = null) -> int
	{

		if typeof this->_redis != "object" {
			this->_connect();
		}

		if keyName {
			let this->_lastKey = this->_prefix . keyName;
		}

		if !value {
			let value = 1;
		}

		return this->_redis->incrBy(this->_lastKey, value);
	}

	/**
	 * Decrement of $keyName by given $value
	 *
	 * @param string keyName
	 * @param int value
	 */
	public function decrement(keyName = null, value = null) -> int
	{

		if typeof this->_redis != "object" {
			this->_connect();
		}

		if keyName {
			let this->_lastKey = this->_prefix . keyName;
		}

		if !value {
			let value = 1;
		}

		return this->_redis->decrBy(this->_lastKey, value);
	}

	/**
	 * Immediately invalidates all existing items.
	 */
	public function flush() -> boolean
	{
		var options, specialKey, keys, key;

		let options = this->_options;

		if !fetch specialKey, options["statsKey"] {
			throw new Exception("Unexpected inconsistency in options");
		}

		if typeof this->_redis != "object" {
			this->_connect();
		}

		if specialKey === false {
			throw new Exception("Cached keys need to be enabled to use this function (options['statsKey'] = 'specialKey')!");
		}

		let keys = this->_redis->sMembers(specialKey);
		if typeof keys == "array" {
			for key in keys {
				this->_redis->sRem(specialKey, key);
				this->_redis->delete(key);
			}
		}

		return true;
	}
}
