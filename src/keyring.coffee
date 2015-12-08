# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Config           = require 'config'
CryptoStorage = require 'crypto_storage'
Keys          = require 'keys'
Nacl          = require 'nacl'
Utils         = require 'utils'

# Manages the public keys of correspondents
class KeyRing
  # storage master key arrives from HW storage
  constructor: (id, strMasterKey = null) ->
    if strMasterKey
      key = Keys.fromString strMasterKey
      @storage = new CryptoStorage(key, id)

    @storage = new CryptoStorage(null, id) unless @storage
    @_ensureKeys()

  # make sure we have all basic keys created
  _ensureKeys: ->
    @_loadCommKey()
    @_loadGuestKeys()

  _loadCommKey: ->
    @comm_key = @getKey 'comm_key'
    return if @comm_key
    @comm_key = Nacl.makeKeyPair()
    @saveKey 'comm_key', @comm_key

  _loadGuestKeys: ->
    @registry = @storage.get('guest_registry') or []
    @guest_keys = {}
    for r in @registry
      @guest_keys[r] = @storage.get("#{r}.guest")

  commFromSeed: (seed) ->
    @comm_key = Nacl.fromSeed Nacl.encode_utf8 seed
    @storage.save('comm_key', @comm_key.toString())

  commFromSecKey: (rawSecKey) ->
    @comm_key = Nacl.fromSecretKey rawSecKey
    @storage.save('comm_key', @comm_key.toString())

  tagByHpk: (hpk) ->
    for own k, v of @guest_keys
      return k if hpk is Nacl.h2(v.fromBase64()).toBase64()

  getMasterKey: ->
    @storage.storage_key.key2str 'key' # to b64 string

  getPubCommKey: ->
    @comm_key.strPubKey()

  saveKey: (tag,key) ->
    @storage.save(tag, key.toString())
    key

  getKey: (tag) ->
    k = @storage.get(tag)
    if k then Keys.fromString k else null

  deleteKey: (tag) ->
    @storage.remove tag

  _addRegistry: (strGuestTag) ->
    return null unless strGuestTag
    @registry.push(strGuestTag) unless @registry.indexOf(strGuestTag) >- 1

  _saveNewGuest: (tag, pk) ->
    return null unless tag and pk
    @storage.save("guest[#{tag}]", pk)
    @storage.save('guest_registry', @registry)

  _removeGuestRecord: (tag) ->
    return null unless tag
    @storage.remove("guest[#{tag}]")
    i = @registry.indexOf tag
    if i >- 1
      @registry.splice(i, 1)
      @storage.save('guest_registry', @registry)

  addGuest: (strGuestTag, b64_pk) ->
    return null unless strGuestTag and b64_pk
    b64_pk = b64_pk.trimLines()
    @_addRegistry strGuestTag
    @guest_keys[strGuestTag] = b64_pk
    @_saveNewGuest(strGuestTag, b64_pk)

  addTempGuest: (strGuestTag,strPubKey) ->
    return null unless strGuestTag and strPubKey
    strPubKey = strPubKey.trimLines()
    @guest_keys[strGuestTag] = strPubKey
    Utils.delay Config.RELAY_SESSION_TIMEOUT, =>
      delete @guest_keys[strGuestTag]

  removeGuest: (strGuestTag) ->
    return null unless strGuestTag and @guest_keys[strGuestTag]
    @guest_keys[strGuestTag] = null # erase the pointer just in case
    delete @guest_keys[strGuestTag]
    @_removeGuestRecord strGuestTag

  getGuestKey: (strGuestTag) ->
    return null unless strGuestTag and @guest_keys[strGuestTag]
    new Keys
      boxPk: @getGuestRecord(strGuestTag).fromBase64()

  getGuestRecord: (strGuestTag) ->
    return null unless strGuestTag and @guest_keys[strGuestTag]
    @guest_keys[strGuestTag]

  # have to call with overseerAuthorized as true for extra safety
  selfDestruct: (overseerAuthorized) ->
    return null unless overseerAuthorized
    rcopy = @registry.slice()
    @removeGuest g for g in rcopy
    @storage.remove 'guest_registry'
    @storage.remove 'comm_key'
    @storage.selfDestruct(overseerAuthorized)

module.exports = KeyRing
window.KeyRing = KeyRing if window.__CRYPTO_DEBUG