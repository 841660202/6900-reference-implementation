// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {FunctionReferenceLib} from "../helpers/FunctionReferenceLib.sol";
import {
    IPlugin,
    ManifestExecutionHook,
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    ManifestExternalCallPermission,
    PluginManifest
} from "../interfaces/IPlugin.sol";
import {FunctionReference, IPluginManager} from "../interfaces/IPluginManager.sol";
import {
    AccountStorage,
    getAccountStorage,
    SelectorData,
    getPermittedCallKey,
    HookGroup,
    PermittedExternalCallData
} from "./AccountStorage.sol";

abstract contract PluginManagerInternals is IPluginManager {
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using FunctionReferenceLib for FunctionReference;

    error ArrayLengthMismatch();
    error ExecutionFunctionAlreadySet(bytes4 selector);
    error InvalidDependenciesProvided();
    error InvalidPluginManifest();
    error MissingPluginDependency(address dependency);
    error NullFunctionReference();
    error NullPlugin();
    error PluginAlreadyInstalled(address plugin);
    error PluginDependencyViolation(address plugin);
    error PluginInstallCallbackFailed(address plugin, bytes revertReason);
    error PluginInterfaceNotSupported(address plugin);
    error PluginNotInstalled(address plugin);
    error RuntimeValidationFunctionAlreadySet(bytes4 selector, FunctionReference validationFunction);
    error UserOpValidationFunctionAlreadySet(bytes4 selector, FunctionReference validationFunction);

    modifier notNullFunction(FunctionReference functionReference) {
        if (functionReference.isEmpty()) {
            revert NullFunctionReference();
        }
        _;
    }

    modifier notNullPlugin(address plugin) {
        if (plugin == address(0)) {
            revert NullPlugin();
        }
        _;
    }

    // Storage update operations
    // 这个函数是用来设置执行函数的
    function _setExecutionFunction(bytes4 selector, address plugin) internal notNullPlugin(plugin) {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        if (_selectorData.plugin != address(0)) {
            revert ExecutionFunctionAlreadySet(selector);
        }

        _selectorData.plugin = plugin;
    }
    // 这个函数是用来移除执行函数的
    function _removeExecutionFunction(bytes4 selector) internal {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        _selectorData.plugin = address(0);
    }
    // 这个函数是用来解析插件的函数的
    function _addUserOpValidationFunction(bytes4 selector, FunctionReference validationFunction)
        internal
        notNullFunction(validationFunction)
    {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        if (!_selectorData.userOpValidation.isEmpty()) {
            revert UserOpValidationFunctionAlreadySet(selector, validationFunction);
        }

        _selectorData.userOpValidation = validationFunction;
    }
    // 这个函数是用来移除用户操作验证函数的
    function _removeUserOpValidationFunction(bytes4 selector, FunctionReference validationFunction)
        internal
        notNullFunction(validationFunction)
    {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        _selectorData.userOpValidation = FunctionReferenceLib._EMPTY_FUNCTION_REFERENCE;
    }
    // 这个函数是用来添加运行时验证函数的
    function _addRuntimeValidationFunction(bytes4 selector, FunctionReference validationFunction)
        internal
        notNullFunction(validationFunction)
    {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        if (!_selectorData.runtimeValidation.isEmpty()) {
            revert RuntimeValidationFunctionAlreadySet(selector, validationFunction);
        }

        _selectorData.runtimeValidation = validationFunction;
    }
    // 这个函数是用来移除运行时验证函数的
    function _removeRuntimeValidationFunction(bytes4 selector, FunctionReference validationFunction)
        internal
        notNullFunction(validationFunction)
    {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        _selectorData.runtimeValidation = FunctionReferenceLib._EMPTY_FUNCTION_REFERENCE;
    }
    // 这个函数是用来添加执行钩子的
    function _addExecHooks(bytes4 selector, FunctionReference preExecHook, FunctionReference postExecHook)
        internal
    {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        _addHooks(_selectorData.executionHooks, preExecHook, postExecHook);
    }
    // 这个函数是用来移除执行钩子的
    function _removeExecHooks(bytes4 selector, FunctionReference preExecHook, FunctionReference postExecHook)
        internal
    {
        SelectorData storage _selectorData = getAccountStorage().selectorData[selector];

        _removeHooks(_selectorData.executionHooks, preExecHook, postExecHook);
    }
    // 这个函数是用来添加钩子的
    function _addHooks(HookGroup storage hooks, FunctionReference preExecHook, FunctionReference postExecHook)
        internal
    {
        if (!preExecHook.isEmpty()) {
            _addOrIncrement(hooks.preHooks, _toSetValue(preExecHook));

            if (!postExecHook.isEmpty()) {
                _addOrIncrement(hooks.associatedPostHooks[preExecHook], _toSetValue(postExecHook));
            }
        } else {
            if (postExecHook.isEmpty()) {
                // both pre and post hooks cannot be null
                revert NullFunctionReference();
            }

            _addOrIncrement(hooks.postOnlyHooks, _toSetValue(postExecHook));
        }
    }
    // 这个函数是用来移除钩子的
    function _removeHooks(HookGroup storage hooks, FunctionReference preExecHook, FunctionReference postExecHook)
        internal
    {
        if (!preExecHook.isEmpty()) {
            _removeOrDecrement(hooks.preHooks, _toSetValue(preExecHook));

            if (!postExecHook.isEmpty()) {
                _removeOrDecrement(hooks.associatedPostHooks[preExecHook], _toSetValue(postExecHook));
            }
        } else {
            // The case where both pre and post hooks are null was checked during installation.

            // May ignore return value, as the manifest hash is validated to ensure that the hook exists.
            _removeOrDecrement(hooks.postOnlyHooks, _toSetValue(postExecHook));
        }
    }
    // 这个函数是用来解析插件的函数的
    function _addPreUserOpValidationHook(bytes4 selector, FunctionReference preUserOpValidationHook)
        internal
        notNullFunction(preUserOpValidationHook)
    {
        _addOrIncrement(
            getAccountStorage().selectorData[selector].preUserOpValidationHooks,
            _toSetValue(preUserOpValidationHook)
        );
    }

    function _removePreUserOpValidationHook(bytes4 selector, FunctionReference preUserOpValidationHook)
        internal
        notNullFunction(preUserOpValidationHook)
    {
        // May ignore return value, as the manifest hash is validated to ensure that the hook exists.
        _removeOrDecrement(
            getAccountStorage().selectorData[selector].preUserOpValidationHooks,
            _toSetValue(preUserOpValidationHook)
        );
    }
    // 这个函数是用来解析插件的函数的
    function _addPreRuntimeValidationHook(bytes4 selector, FunctionReference preRuntimeValidationHook)
        internal
        notNullFunction(preRuntimeValidationHook)
    {
        _addOrIncrement(
            getAccountStorage().selectorData[selector].preRuntimeValidationHooks,
            _toSetValue(preRuntimeValidationHook)
        );
    }
    // 这个函数是用来移除运行时验证函数的
    function _removePreRuntimeValidationHook(bytes4 selector, FunctionReference preRuntimeValidationHook)
        internal
        notNullFunction(preRuntimeValidationHook)
    {
        // May ignore return value, as the manifest hash is validated to ensure that the hook exists.
        _removeOrDecrement(
            getAccountStorage().selectorData[selector].preRuntimeValidationHooks,
            _toSetValue(preRuntimeValidationHook)
        );
    }
    // 这个函数是用来解析插件的函数的
    function _installPlugin(
        address plugin,
        bytes32 manifestHash,
        bytes memory pluginInstallData,
        FunctionReference[] memory dependencies
    ) internal {
        AccountStorage storage _storage = getAccountStorage();

        // Check if the plugin exists.
        // 这是通过插件的地址来判断的
        if (!_storage.plugins.add(plugin)) {
            revert PluginAlreadyInstalled(plugin);
        }

        // Check that the plugin supports the IPlugin interface.
        // 检测插件是否支持 IPlugin 接口
        if (!ERC165Checker.supportsInterface(plugin, type(IPlugin).interfaceId)) {
            revert PluginInterfaceNotSupported(plugin);
        }

        // Check manifest hash.
        // 检查插件的 manifestHash 是否正确，为了保证插件的安全性
        PluginManifest memory manifest = IPlugin(plugin).pluginManifest();
        if (!_isValidPluginManifest(manifest, manifestHash)) {
            revert InvalidPluginManifest();
        }

        // Check that the dependencies match the manifest.
        // 检查插件的依赖是否正确
        if (dependencies.length != manifest.dependencyInterfaceIds.length) {
            revert InvalidDependenciesProvided();
        }

        uint256 length = dependencies.length;
        for (uint256 i = 0; i < length;) {
            // Check the dependency interface id over the address of the dependency.
            (address dependencyAddr,) = dependencies[i].unpack();

            // Check that the dependency is installed.
            if (_storage.pluginData[dependencyAddr].manifestHash == bytes32(0)) {
                revert MissingPluginDependency(dependencyAddr);
            }

            // Check that the dependency supports the expected interface.
            if (!ERC165Checker.supportsInterface(dependencyAddr, manifest.dependencyInterfaceIds[i])) {
                revert InvalidDependenciesProvided();
            }

            // Increment the dependency's dependents counter.
            _storage.pluginData[dependencyAddr].dependentCount += 1;

            unchecked {
                ++i;
            }
        }

        // Add the plugin metadata to the account
        _storage.pluginData[plugin].manifestHash = manifestHash;
        _storage.pluginData[plugin].dependencies = dependencies;

        // Update components according to the manifest.

        // Mark whether or not this plugin may spend native token amounts
        // 标记插件是否可以花费原生代币
        if (manifest.canSpendNativeToken) {
            _storage.pluginData[plugin].canSpendNativeToken = true;
        }

        length = manifest.executionFunctions.length;
        for (uint256 i = 0; i < length;) {
            _setExecutionFunction(manifest.executionFunctions[i], plugin);

            unchecked {
                ++i;
            }
        }

        // Add installed plugin and selectors this plugin can call
        length = manifest.permittedExecutionSelectors.length;
        for (uint256 i = 0; i < length;) {
            // If there are duplicates, this will just enable the flag again. This is not a problem, since the
            // boolean will be set to false twice during uninstall, which is fine.
            // 如果有重复的，这将再次启用标志。这不是问题，因为在卸载期间，布尔值将被设置两次为false，这是可以的。
            _storage.callPermitted[getPermittedCallKey(plugin, manifest.permittedExecutionSelectors[i])] = true;

            unchecked {
                ++i;
            }
        }

        // Add the permitted external calls to the account.
        if (manifest.permitAnyExternalAddress) {
            _storage.pluginData[plugin].anyExternalExecPermitted = true;
        } else {
            // Only store the specific permitted external calls if "permit any" flag was not set.
            // 只有在没有设置“允许任何”标志时，才存储特定的允许的外部调用
            length = manifest.permittedExternalCalls.length;
            for (uint256 i = 0; i < length;) {
                // 获取插件的允许的外部调用
                ManifestExternalCallPermission memory externalCallPermission = manifest.permittedExternalCalls[i];
                // 获取插件的允许的外部调用的数据
                PermittedExternalCallData storage permittedExternalCallData =
                    _storage.permittedExternalCalls[IPlugin(plugin)][externalCallPermission.externalAddress];
                // 设置插件的允许的外部调用的地址
                permittedExternalCallData.addressPermitted = true;
                // 如果在构造函数中设置了“允许任何选择器”标志，只有在构造函数中设置了“允许任何选择器”标志时，才清除此标志。
                if (externalCallPermission.permitAnySelector) {
                    permittedExternalCallData.anySelectorPermitted = true;
                } else {
                    uint256 externalContractSelectorsLength = externalCallPermission.selectors.length;
                    // 可以允许多个选择器，这些选择器对应的外部合约地址是一样的，这些是被允许的外部调用
                    for (uint256 j = 0; j < externalContractSelectorsLength;) {
                        permittedExternalCallData.permittedSelectors[externalCallPermission.selectors[j]] = true;

                        unchecked {
                            ++j;
                        }
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        length = manifest.userOpValidationFunctions.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mv = manifest.userOpValidationFunctions[i];
            _addUserOpValidationFunction(
                mv.executionSelector,
                _resolveManifestFunction(
                    mv.associatedFunction, plugin, dependencies, ManifestAssociatedFunctionType.NONE
                )
            );

            unchecked {
                ++i;
            }
        }

        length = manifest.runtimeValidationFunctions.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mv = manifest.runtimeValidationFunctions[i];
            _addRuntimeValidationFunction(
                mv.executionSelector,
                _resolveManifestFunction(
                    mv.associatedFunction,
                    plugin,
                    dependencies,
                    ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW
                )
            );

            unchecked {
                ++i;
            }
        }

        // Hooks are not allowed to be provided as dependencies, so we use an empty array for resolving them.
        FunctionReference[] memory emptyDependencies;

        length = manifest.preUserOpValidationHooks.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mh = manifest.preUserOpValidationHooks[i];
            _addPreUserOpValidationHook(
                mh.executionSelector,
                _resolveManifestFunction(
                    mh.associatedFunction,
                    plugin,
                    emptyDependencies,
                    ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY
                )
            );

            unchecked {
                ++i;
            }
        }

        length = manifest.preRuntimeValidationHooks.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mh = manifest.preRuntimeValidationHooks[i];
            _addPreRuntimeValidationHook(
                mh.executionSelector,
                _resolveManifestFunction(
                    mh.associatedFunction,
                    plugin,
                    emptyDependencies,
                    ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY
                )
            );
            unchecked {
                ++i;
            }
        }

        length = manifest.executionHooks.length;
        for (uint256 i = 0; i < length;) {
            ManifestExecutionHook memory mh = manifest.executionHooks[i];
            _addExecHooks(
                mh.executionSelector,
                _resolveManifestFunction(
                    mh.preExecHook, plugin, emptyDependencies, ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY
                ),
                _resolveManifestFunction(
                    mh.postExecHook, plugin, emptyDependencies, ManifestAssociatedFunctionType.NONE
                )
            );

            unchecked {
                ++i;
            }
        }

        length = manifest.interfaceIds.length;
        for (uint256 i = 0; i < length;) {
            _storage.supportedIfaces[manifest.interfaceIds[i]] += 1;
            unchecked {
                ++i;
            }
        }

        // Initialize the plugin storage for the account.
        // 初始化插件的存储
        // solhint-disable-next-line no-empty-blocks
        try IPlugin(plugin).onInstall(pluginInstallData) {}
        
        catch (bytes memory revertReason) {
            revert PluginInstallCallbackFailed(plugin, revertReason);
        }

        emit PluginInstalled(plugin, manifestHash, dependencies);
    }

    function _uninstallPlugin(address plugin, PluginManifest memory manifest, bytes memory uninstallData)
        internal
    {
        AccountStorage storage _storage = getAccountStorage();

        // Check if the plugin exists.
        if (!_storage.plugins.remove(plugin)) {
            revert PluginNotInstalled(plugin);
        }

        // Check manifest hash.
        bytes32 manifestHash = _storage.pluginData[plugin].manifestHash;
        if (!_isValidPluginManifest(manifest, manifestHash)) {
            revert InvalidPluginManifest();
        }

        // Ensure that there are no dependent plugins.
        if (_storage.pluginData[plugin].dependentCount != 0) {
            revert PluginDependencyViolation(plugin);
        }

        // Remove this plugin as a dependent from its dependencies.
        FunctionReference[] memory dependencies = _storage.pluginData[plugin].dependencies;
        uint256 length = dependencies.length;
        for (uint256 i = 0; i < length;) {
            FunctionReference dependency = dependencies[i];
            (address dependencyAddr,) = dependency.unpack();

            // Decrement the dependent count for the dependency function.
            _storage.pluginData[dependencyAddr].dependentCount -= 1;

            unchecked {
                ++i;
            }
        }

        // Remove components according to the manifest, in reverse order (by component type) of their installation.

        // Hooks are not allowed to be provided as dependencies, so we use an empty array for resolving them.
        FunctionReference[] memory emptyDependencies;

        length = manifest.executionHooks.length;
        for (uint256 i = 0; i < length;) {
            ManifestExecutionHook memory mh = manifest.executionHooks[i];
            _removeExecHooks(
                mh.executionSelector,
                _resolveManifestFunction(
                    mh.preExecHook, plugin, emptyDependencies, ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY
                ),
                _resolveManifestFunction(
                    mh.postExecHook, plugin, emptyDependencies, ManifestAssociatedFunctionType.NONE
                )
            );

            unchecked {
                ++i;
            }
        }

        length = manifest.preRuntimeValidationHooks.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mh = manifest.preRuntimeValidationHooks[i];
            _removePreRuntimeValidationHook(
                mh.executionSelector,
                _resolveManifestFunction(
                    mh.associatedFunction,
                    plugin,
                    emptyDependencies,
                    ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY
                )
            );

            unchecked {
                ++i;
            }
        }

        length = manifest.preUserOpValidationHooks.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mh = manifest.preUserOpValidationHooks[i];
            _removePreUserOpValidationHook(
                mh.executionSelector,
                _resolveManifestFunction(
                    mh.associatedFunction,
                    plugin,
                    emptyDependencies,
                    ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY
                )
            );

            unchecked {
                ++i;
            }
        }

        length = manifest.runtimeValidationFunctions.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mv = manifest.runtimeValidationFunctions[i];
            _removeRuntimeValidationFunction(
                mv.executionSelector,
                _resolveManifestFunction(
                    mv.associatedFunction,
                    plugin,
                    dependencies,
                    ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW
                )
            );

            unchecked {
                ++i;
            }
        }

        length = manifest.userOpValidationFunctions.length;
        for (uint256 i = 0; i < length;) {
            ManifestAssociatedFunction memory mv = manifest.userOpValidationFunctions[i];
            _removeUserOpValidationFunction(
                mv.executionSelector,
                _resolveManifestFunction(
                    mv.associatedFunction, plugin, dependencies, ManifestAssociatedFunctionType.NONE
                )
            );

            unchecked {
                ++i;
            }
        }

        // remove external call permissions
        // 删除外部调用权限
        if (manifest.permitAnyExternalAddress) {
            // Only clear if it was set during install time
            _storage.pluginData[plugin].anyExternalExecPermitted = false;
        } else {
            // Only clear the specific permitted external calls if "permit any" flag was not set.
            length = manifest.permittedExternalCalls.length;
            for (uint256 i = 0; i < length;) {
                ManifestExternalCallPermission memory externalCallPermission = manifest.permittedExternalCalls[i];

                PermittedExternalCallData storage permittedExternalCallData =
                    _storage.permittedExternalCalls[IPlugin(plugin)][externalCallPermission.externalAddress];

                permittedExternalCallData.addressPermitted = false;

                // Only clear this flag if it was set in the constructor.
                if (externalCallPermission.permitAnySelector) {
                    permittedExternalCallData.anySelectorPermitted = false;
                } else {
                    uint256 externalContractSelectorsLength = externalCallPermission.selectors.length;
                    for (uint256 j = 0; j < externalContractSelectorsLength;) {
                        permittedExternalCallData.permittedSelectors[externalCallPermission.selectors[j]] = false;

                        unchecked {
                            ++j;
                        }
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        length = manifest.permittedExecutionSelectors.length;
        for (uint256 i = 0; i < length;) {
            _storage.callPermitted[getPermittedCallKey(plugin, manifest.permittedExecutionSelectors[i])] = false;

            unchecked {
                ++i;
            }
        }

        length = manifest.executionFunctions.length;
        for (uint256 i = 0; i < length;) {
            _removeExecutionFunction(manifest.executionFunctions[i]);

            unchecked {
                ++i;
            }
        }

        length = manifest.interfaceIds.length;
        for (uint256 i = 0; i < length;) {
            _storage.supportedIfaces[manifest.interfaceIds[i]] -= 1;
            unchecked {
                ++i;
            }
        }

        // Remove the plugin metadata from the account.
        delete _storage.pluginData[plugin];

        // Clear the plugin storage for the account.
        bool onUninstallSuccess = true;
        // solhint-disable-next-line no-empty-blocks
        try IPlugin(plugin).onUninstall(uninstallData) {}
        catch {
            onUninstallSuccess = false;
        }

        emit PluginUninstalled(plugin, onUninstallSuccess);
    }

    function _addOrIncrement(EnumerableMap.Bytes32ToUintMap storage map, bytes32 key) internal {
        (bool success, uint256 value) = map.tryGet(key);
        map.set(key, success ? value + 1 : 0);
    }

    /// @return True if the key was removed or its value was decremented, false if the key was not found.
    function _removeOrDecrement(EnumerableMap.Bytes32ToUintMap storage map, bytes32 key) internal returns (bool) {
        (bool success, uint256 value) = map.tryGet(key);
        if (!success) {
            return false;
        }
        if (value == 0) {
            map.remove(key);
        } else {
            map.set(key, value - 1);
        }
        return true;
    }

    function _toSetValue(FunctionReference functionReference) internal pure returns (bytes32) {
        return bytes32(FunctionReference.unwrap(functionReference));
    }

    function _toFunctionReference(bytes32 setValue) internal pure returns (FunctionReference) {
        return FunctionReference.wrap(bytes21(setValue));
    }

    function _isValidPluginManifest(PluginManifest memory manifest, bytes32 manifestHash)
        internal
        pure
        returns (bool)
    {
        return manifestHash == keccak256(abi.encode(manifest));
    }

    function _resolveManifestFunction(
        ManifestFunction memory manifestFunction,
        address plugin,
        FunctionReference[] memory dependencies,
        // Indicates which magic value, if any, is permissible for the function to resolve.
        ManifestAssociatedFunctionType allowedMagicValue
    ) internal pure returns (FunctionReference) {
        if (manifestFunction.functionType == ManifestAssociatedFunctionType.SELF) {
            return FunctionReferenceLib.pack(plugin, manifestFunction.functionId);
        } else if (manifestFunction.functionType == ManifestAssociatedFunctionType.DEPENDENCY) {
            if (manifestFunction.dependencyIndex >= dependencies.length) {
                revert InvalidPluginManifest();
            }
            return dependencies[manifestFunction.dependencyIndex];
        } else if (manifestFunction.functionType == ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW)
        {
            if (allowedMagicValue == ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW) {
                return FunctionReferenceLib._RUNTIME_VALIDATION_ALWAYS_ALLOW;
            } else {
                revert InvalidPluginManifest();
            }
        } else if (manifestFunction.functionType == ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY) {
            if (allowedMagicValue == ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY) {
                return FunctionReferenceLib._PRE_HOOK_ALWAYS_DENY;
            } else {
                revert InvalidPluginManifest();
            }
        }
        return FunctionReferenceLib._EMPTY_FUNCTION_REFERENCE; // Empty checks are done elsewhere
    }
}
