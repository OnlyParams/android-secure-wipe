<script>
  // SecureWipe Wizard - Main Application Component
  // OnlyParams, a division of Ciphracore Systems LLC
  // Phase 3: Full frontend implementation with Tauri backend integration

  import { onMount, onDestroy } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { listen } from '@tauri-apps/api/event';

  // ============================================================================
  // State
  // ============================================================================

  // Wizard step state
  let currentStep = $state(0);
  const steps = ['Prepare', 'Options', 'Confirm', 'Progress', 'Done'];

  // ADB/Device state
  let adbStatus = $state({ installed: false, version: null, devices_connected: 0 });
  let deviceInfo = $state({ id: '', model: '', brand: '', android_version: '' });
  let storageInfo = $state({ total_mb: 0, used_mb: 0, available_mb: 0, percent_used: 0 });
  let deviceConnected = $state(false);
  let isCheckingDevice = $state(false);
  let deviceError = $state('');

  // Wipe options state
  let wipeMode = $state('quick');
  let passes = $state(3);
  let chunkSizeMb = $state(1024);

  // Progress state
  let wipeProgress = $state(0);
  let currentPass = $state(0);
  let totalPasses = $state(0);
  let progressPhase = $state('');
  let progressMessage = $state('');
  let wipeLog = $state([]);
  let isWiping = $state(false);
  let isAborting = $state(false);
  let wipeComplete = $state(false);
  let wipeError = $state('');

  // Brand-specific instructions
  let resetInstructions = $state([]);

  // Event listeners cleanup
  let unlistenProgress = null;
  let unlistenComplete = null;
  let unlistenAborted = null;

  // Log container ref for auto-scroll
  let logContainer = $state(null);

  // ============================================================================
  // Computed Values
  // ============================================================================

  let eta = $derived(wipeMode === 'quick' ? '~15 mins' : '1-3+ hrs');

  let storageDisplay = $derived({
    total: (storageInfo.total_mb / 1024).toFixed(1),
    used: (storageInfo.used_mb / 1024).toFixed(1),
    available: (storageInfo.available_mb / 1024).toFixed(1),
  });

  let canProceed = $derived(
    currentStep === 0 ? deviceConnected :
    currentStep === 1 ? true :
    currentStep === 2 ? true :
    currentStep === 3 ? wipeComplete :
    true
  );

  // ============================================================================
  // Lifecycle
  // ============================================================================

  onMount(async () => {
    console.log('SecureWipe Wizard initialized');

    // Set up event listeners for progress streaming
    unlistenProgress = await listen('wipe-progress', (event) => {
      const data = event.payload;
      wipeProgress = data.percent || 0;
      currentPass = data.pass || 0;
      totalPasses = data.total_passes || passes;
      progressPhase = data.phase || '';
      progressMessage = data.message || '';

      if (data.message) {
        addLog(data.message);
      }
    });

    unlistenComplete = await listen('wipe-complete', (event) => {
      const data = event.payload;
      isWiping = false;
      wipeComplete = data.success;
      if (data.success) {
        wipeProgress = 100;
        addLog('✓ Wipe completed successfully!');
      } else {
        wipeError = 'Wipe failed. Please check device connection.';
        addLog('✗ Wipe failed');
      }
    });

    unlistenAborted = await listen('wipe-aborted', (event) => {
      const data = event.payload;
      isWiping = false;
      isAborting = false;
      wipeProgress = 0;
      currentStep = 2; // Go back to confirm step
      addLog('✗ Wipe aborted by user');
      addLog(data.message || 'Temporary files cleaned up.');
    });

    // Auto-check ADB on mount
    await checkAdbStatus();
  });

  onDestroy(() => {
    if (unlistenProgress) unlistenProgress();
    if (unlistenComplete) unlistenComplete();
    if (unlistenAborted) unlistenAborted();
  });

  // ============================================================================
  // Functions
  // ============================================================================

  function addLog(message) {
    const timestamp = new Date().toLocaleTimeString();
    wipeLog = [...wipeLog, `[${timestamp}] ${message}`];
    // Auto-scroll to bottom after adding log
    if (logContainer) {
      // Use setTimeout to ensure DOM has updated
      setTimeout(() => {
        logContainer.scrollTop = logContainer.scrollHeight;
      }, 0);
    }
  }

  async function checkAdbStatus() {
    isCheckingDevice = true;
    deviceError = '';

    try {
      // First check if ADB is installed
      adbStatus = await invoke('check_adb_status');

      if (!adbStatus.installed) {
        deviceError = 'ADB not found. Please install Android SDK Platform Tools.';
        deviceConnected = false;
        return;
      }

      if (adbStatus.devices_connected === 0) {
        deviceError = 'No device connected. Please connect your Android phone via USB.';
        deviceConnected = false;
        return;
      }

      // Get detailed device info
      deviceInfo = await invoke('check_adb');
      deviceConnected = true;

      // Get storage info
      storageInfo = await invoke('get_storage_info', { deviceId: deviceInfo.id });

      // Get brand-specific instructions
      resetInstructions = await invoke('get_instructions', {
        brand: deviceInfo.brand,
        model: deviceInfo.model
      });

    } catch (err) {
      deviceError = typeof err === 'string' ? err : err.message || 'Failed to detect device';
      deviceConnected = false;
    } finally {
      isCheckingDevice = false;
    }
  }

  async function startWipe() {
    isWiping = true;
    wipeComplete = false;
    wipeError = '';
    wipeProgress = 0;
    wipeLog = [];

    addLog(`Starting ${wipeMode} wipe with ${passes} passes...`);

    try {
      const config = {
        mode: wipeMode,
        passes: passes,
        size_mb: wipeMode === 'quick' ? chunkSizeMb : null,
        double_reset: false, // Factory reset handled manually via instructions
      };

      const result = await invoke('run_wipe', {
        deviceId: deviceInfo.id,
        config: config
      });

      addLog(result);
      wipeComplete = true;
      wipeProgress = 100;

    } catch (err) {
      wipeError = typeof err === 'string' ? err : err.message || 'Wipe failed';
      addLog(`Error: ${wipeError}`);
      isWiping = false;
    }
  }

  async function abortWipe() {
    if (!isWiping || isAborting) return;

    isAborting = true;
    addLog('Aborting wipe operation...');

    try {
      const result = await invoke('abort_wipe');
      addLog(result);
    } catch (err) {
      addLog(`Abort error: ${err}`);
      // Even if abort fails, reset state
      isWiping = false;
      isAborting = false;
    }
  }

  function nextStep() {
    if (currentStep < steps.length - 1) {
      // Special handling for confirm -> progress transition
      if (currentStep === 2) {
        currentStep++;
        startWipe();
      } else {
        currentStep++;
      }
    }
  }

  function prevStep() {
    if (currentStep > 0 && !isWiping) {
      currentStep--;
    }
  }

  function resetWizard() {
    currentStep = 0;
    wipeProgress = 0;
    wipeLog = [];
    isWiping = false;
    wipeComplete = false;
    wipeError = '';
  }
</script>

<main class="min-h-screen bg-gray-50 flex flex-col">
  <!-- Header -->
  <header class="bg-teal-700 text-white px-6 py-4 shadow-md no-select">
    <h1 class="text-xl font-bold">SecureWipe Wizard</h1>
    <p class="text-teal-200 text-sm">by OnlyParams</p>
  </header>

  <!-- Step Indicator -->
  <nav class="bg-white border-b px-6 py-3 no-select">
    <ol class="flex items-center justify-center space-x-4">
      {#each steps as step, i}
        <li class="flex items-center">
          <span
            class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium transition-colors
                   {i === currentStep ? 'bg-teal-600 text-white' :
                    i < currentStep ? 'bg-teal-200 text-teal-800' : 'bg-gray-200 text-gray-500'}"
          >
            {#if i < currentStep}
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
              </svg>
            {:else}
              {i + 1}
            {/if}
          </span>
          <span class="ml-2 text-sm hidden sm:inline {i === currentStep ? 'text-teal-700 font-medium' : 'text-gray-500'}">
            {step}
          </span>
          {#if i < steps.length - 1}
            <svg class="w-4 h-4 mx-3 text-gray-300" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" />
            </svg>
          {/if}
        </li>
      {/each}
    </ol>
  </nav>

  <!-- Main Content Area -->
  <div class="flex-1 p-6 overflow-auto">
    {#if currentStep === 0}
      <!-- ================================================================ -->
      <!-- Step 1: Prepare - Device Detection -->
      <!-- ================================================================ -->
      <div class="max-w-lg mx-auto">
        <h2 class="text-2xl font-bold text-gray-800 mb-4">Prepare Your Device</h2>

        <!-- Prerequisites Notice -->
        <div class="bg-amber-50 border border-amber-300 rounded-xl p-4 mb-4 text-left">
          <h3 class="font-semibold text-amber-800 text-sm mb-2">Before using this tool:</h3>
          <ul class="text-xs text-amber-700 space-y-1 ml-4 list-disc">
            <li><strong>Back up</strong> all data you want to keep</li>
            <li><strong>Sign out</strong> of all Google accounts</li>
            <li><strong>Remove</strong> OEM accounts (Samsung, Xiaomi, etc.)</li>
            <li><strong>Disable</strong> Find My Device</li>
            <li><strong>Factory reset</strong> the phone first</li>
          </ul>
          <p class="text-xs text-amber-600 mt-2">
            This tool overwrites free space <em>after</em> reset. We are not responsible for data loss.
          </p>
          <p class="text-xs text-amber-700 mt-1">
            <a href="https://github.com/OnlyParams/android-secure-wipe#readme" target="_blank" class="underline hover:text-amber-900">See full instructions in docs →</a>
          </p>
        </div>

        <div class="bg-white rounded-xl shadow-lg p-6 space-y-5">
          <!-- Device Status Card -->
          <div class="p-4 rounded-lg {deviceConnected ? 'bg-green-50 border border-green-200' : 'bg-gray-50 border border-gray-200'}">
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-3">
                <!-- Device Icon -->
                <div class="w-12 h-12 rounded-lg flex items-center justify-center {deviceConnected ? 'bg-green-100' : 'bg-gray-200'}">
                  <svg class="w-6 h-6 {deviceConnected ? 'text-green-600' : 'text-gray-400'}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                  </svg>
                </div>
                <div>
                  <p class="font-semibold text-gray-800">
                    {deviceConnected ? `${deviceInfo.brand} ${deviceInfo.model}` : 'No Device Detected'}
                  </p>
                  <p class="text-sm text-gray-500">
                    {#if deviceConnected}
                      Android {deviceInfo.android_version} • ID: {deviceInfo.id.slice(0, 12)}...
                    {:else}
                      Connect your Android phone via USB
                    {/if}
                  </p>
                </div>
              </div>
              <span class="w-3 h-3 rounded-full {deviceConnected ? 'bg-green-500 animate-pulse' : 'bg-red-400'}"></span>
            </div>
          </div>

          <!-- Storage Info (when connected) -->
          {#if deviceConnected}
            <div class="p-4 bg-teal-50 rounded-lg border border-teal-100">
              <div class="flex items-center justify-between mb-2">
                <span class="text-sm font-medium text-teal-800">Storage</span>
                <span class="text-sm text-teal-600">{storageInfo.percent_used}% used</span>
              </div>
              <div class="h-2 bg-teal-100 rounded-full overflow-hidden">
                <div
                  class="h-full bg-teal-500 rounded-full transition-all duration-500"
                  style="width: {storageInfo.percent_used}%"
                ></div>
              </div>
              <div class="flex justify-between mt-2 text-xs text-teal-600">
                <span>{storageDisplay.used} GB used</span>
                <span>{storageDisplay.available} GB free of {storageDisplay.total} GB</span>
              </div>
            </div>
          {/if}

          <!-- ADB Status -->
          {#if adbStatus.installed}
            <div class="flex items-center text-sm text-gray-500">
              <svg class="w-4 h-4 mr-2 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
              </svg>
              ADB Ready: {adbStatus.version?.split('\n')[0] || 'Installed'}
            </div>
          {/if}

          <!-- Error Display -->
          {#if deviceError}
            <div class="p-4 bg-red-50 border border-red-200 rounded-lg">
              <p class="text-red-700 text-sm">{deviceError}</p>
            </div>
          {/if}

          <!-- Check Connection Button -->
          <button
            onclick={checkAdbStatus}
            disabled={isCheckingDevice}
            class="w-full py-3 px-4 bg-teal-600 text-white rounded-lg hover:bg-teal-700
                   focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2
                   disabled:opacity-50 disabled:cursor-not-allowed transition-all
                   flex items-center justify-center space-x-2"
          >
            {#if isCheckingDevice}
              <svg class="animate-spin w-5 h-5" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              <span>Checking...</span>
            {:else}
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              <span>{deviceConnected ? 'Refresh Connection' : 'Check Connection'}</span>
            {/if}
          </button>

          <!-- Setup Instructions -->
          <div class="text-sm text-gray-600 space-y-2 pt-2 border-t">
            <p class="font-medium">Before you start:</p>
            <ul class="list-none space-y-2">
              <li class="flex items-start">
                <svg class="w-5 h-5 mr-2 text-teal-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>Enable <strong>USB Debugging</strong> in Developer Options</span>
              </li>
              <li class="flex items-start">
                <svg class="w-5 h-5 mr-2 text-teal-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>Connect via USB cable (data-capable)</span>
              </li>
              <li class="flex items-start">
                <svg class="w-5 h-5 mr-2 text-teal-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>Authorize this computer when prompted on phone</span>
              </li>
            </ul>
          </div>
        </div>
      </div>

    {:else if currentStep === 1}
      <!-- ================================================================ -->
      <!-- Step 2: Options - Wipe Mode Selection -->
      <!-- ================================================================ -->
      <div class="max-w-lg mx-auto">
        <h2 class="text-2xl font-bold text-gray-800 mb-4 text-center">Choose Your Wipe Mode</h2>

        <div class="space-y-4">
          <!-- Quick Mode Card -->
          <button
            onclick={() => wipeMode = 'quick'}
            class="w-full text-left p-5 rounded-xl border-2 transition-all hover:shadow-md
                   {wipeMode === 'quick' ? 'border-green-500 bg-green-50 shadow-md' : 'border-gray-200 bg-white hover:border-green-300'}"
          >
            <div class="flex items-start justify-between">
              <div class="flex items-center">
                <div class="w-12 h-12 rounded-lg flex items-center justify-center {wipeMode === 'quick' ? 'bg-green-100' : 'bg-gray-100'}">
                  <svg class="w-6 h-6 {wipeMode === 'quick' ? 'text-green-600' : 'text-gray-400'}" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" />
                  </svg>
                </div>
                <div class="ml-4">
                  <h3 class="font-semibold text-lg text-gray-800">Quick Wipe</h3>
                  <p class="text-sm text-gray-500 mt-1">NIST-compliant for everyday security</p>
                </div>
              </div>
              <div class="w-5 h-5 rounded-full border-2 flex items-center justify-center {wipeMode === 'quick' ? 'border-green-500 bg-green-500' : 'border-gray-300'}">
                {#if wipeMode === 'quick'}
                  <svg class="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                  </svg>
                {/if}
              </div>
            </div>
            <p class="text-sm text-gray-600 mt-3 ml-16">
              3 passes × 1GB chunks + factory reset. Perfect for trade-ins and donations.
            </p>
            <div class="mt-3 ml-16 flex items-center text-sm">
              <svg class="w-4 h-4 mr-1 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" />
              </svg>
              <span class="text-green-600 font-medium">~15 minutes</span>
            </div>
          </button>

          <!-- Full Mode Card -->
          <button
            onclick={() => wipeMode = 'full'}
            class="w-full text-left p-5 rounded-xl border-2 transition-all hover:shadow-md
                   {wipeMode === 'full' ? 'border-teal-500 bg-teal-50 shadow-md' : 'border-gray-200 bg-white hover:border-teal-300'}"
          >
            <div class="flex items-start justify-between">
              <div class="flex items-center">
                <div class="w-12 h-12 rounded-lg flex items-center justify-center {wipeMode === 'full' ? 'bg-teal-100' : 'bg-gray-100'}">
                  <svg class="w-6 h-6 {wipeMode === 'full' ? 'text-teal-600' : 'text-gray-400'}" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" />
                  </svg>
                </div>
                <div class="ml-4">
                  <h3 class="font-semibold text-lg text-gray-800">Full Wipe</h3>
                  <p class="text-sm text-gray-500 mt-1">Maximum security for sensitive data</p>
                </div>
              </div>
              <div class="w-5 h-5 rounded-full border-2 flex items-center justify-center {wipeMode === 'full' ? 'border-teal-500 bg-teal-500' : 'border-gray-300'}">
                {#if wipeMode === 'full'}
                  <svg class="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                  </svg>
                {/if}
              </div>
            </div>
            <p class="text-sm text-gray-600 mt-3 ml-16">
              Multi-pass 95% storage fill. For when you need absolute certainty.
            </p>
            <div class="mt-3 ml-16 flex items-center text-sm">
              <svg class="w-4 h-4 mr-1 text-teal-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" />
              </svg>
              <span class="text-teal-600 font-medium">1-3+ hours</span>
            </div>
          </button>
        </div>

        <!-- Passes Slider -->
        <div class="mt-6 p-5 bg-white rounded-xl shadow-md">
          <div class="flex items-center justify-between mb-3">
            <label class="font-medium text-gray-700">Overwrite Passes</label>
            <span class="text-2xl font-bold text-teal-600">{passes}</span>
          </div>
          <input
            type="range"
            bind:value={passes}
            min="1"
            max="10"
            class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-teal-600"
          />
          <div class="flex justify-between text-xs text-gray-500 mt-1">
            <span>1 (Fast)</span>
            <span>3 (Recommended)</span>
            <span>10 (Paranoid)</span>
          </div>
        </div>

        <!-- Quick Mode: Chunk Size -->
        {#if wipeMode === 'quick'}
          <div class="mt-4 p-5 bg-white rounded-xl shadow-md">
            <div class="flex items-center justify-between mb-3">
              <label class="font-medium text-gray-700">Chunk Size</label>
              <span class="text-lg font-bold text-teal-600">{chunkSizeMb} MB</span>
            </div>
            <input
              type="range"
              bind:value={chunkSizeMb}
              min="256"
              max="4096"
              step="256"
              class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-teal-600"
            />
            <div class="flex justify-between text-xs text-gray-500 mt-1">
              <span>256 MB</span>
              <span>1 GB</span>
              <span>4 GB</span>
            </div>
          </div>
        {/if}

      </div>

    {:else if currentStep === 2}
      <!-- ================================================================ -->
      <!-- Step 3: Confirm - Recap & Start -->
      <!-- ================================================================ -->
      <div class="max-w-lg mx-auto">
        <h2 class="text-2xl font-bold text-gray-800 mb-4">Confirm Your Settings</h2>

        <div class="bg-white rounded-xl shadow-lg p-6 space-y-5">
          <!-- Warning Banner -->
          <div class="p-4 bg-amber-50 border border-amber-200 rounded-lg flex items-start">
            <svg class="w-6 h-6 text-amber-500 mr-3 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
            </svg>
            <div>
              <p class="font-semibold text-amber-800">This action is irreversible</p>
              <p class="text-sm text-amber-700 mt-1">All data on your device will be permanently erased.</p>
            </div>
          </div>

          <!-- Device Summary -->
          <div class="p-4 bg-gray-50 rounded-lg">
            <div class="flex items-center space-x-3">
              <div class="w-10 h-10 rounded-lg bg-teal-100 flex items-center justify-center">
                <svg class="w-5 h-5 text-teal-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                </svg>
              </div>
              <div>
                <p class="font-medium text-gray-800">{deviceInfo.brand} {deviceInfo.model}</p>
                <p class="text-sm text-gray-500">Android {deviceInfo.android_version}</p>
              </div>
            </div>
          </div>

          <!-- Settings Summary -->
          <dl class="divide-y divide-gray-100">
            <div class="py-3 flex justify-between items-center">
              <dt class="text-gray-500 flex items-center">
                <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
                </svg>
                Wipe Mode
              </dt>
              <dd class="font-semibold text-gray-900 capitalize">{wipeMode}</dd>
            </div>
            <div class="py-3 flex justify-between items-center">
              <dt class="text-gray-500 flex items-center">
                <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clip-rule="evenodd" />
                </svg>
                Overwrite Passes
              </dt>
              <dd class="font-semibold text-gray-900">{passes}</dd>
            </div>
            {#if wipeMode === 'quick'}
              <div class="py-3 flex justify-between items-center">
                <dt class="text-gray-500 flex items-center">
                  <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M3 12v3c0 1.657 3.134 3 7 3s7-1.343 7-3v-3c0 1.657-3.134 3-7 3s-7-1.343-7-3z" />
                    <path d="M3 7v3c0 1.657 3.134 3 7 3s7-1.343 7-3V7c0 1.657-3.134 3-7 3S3 8.657 3 7z" />
                    <path d="M17 5c0 1.657-3.134 3-7 3S3 6.657 3 5s3.134-3 7-3 7 1.343 7 3z" />
                  </svg>
                  Chunk Size
                </dt>
                <dd class="font-semibold text-gray-900">{chunkSizeMb} MB</dd>
              </div>
            {/if}
            <div class="py-3 flex justify-between items-center">
              <dt class="text-gray-500 flex items-center">
                <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
                </svg>
                Estimated Time
              </dt>
              <dd class="font-semibold text-teal-600">{eta}</dd>
            </div>
          </dl>

          <!-- Big Start Button -->
          <button
            onclick={nextStep}
            class="w-full py-4 px-6 bg-gradient-to-r from-teal-600 to-teal-500 text-white text-lg font-semibold rounded-xl
                   hover:from-teal-700 hover:to-teal-600 focus:outline-none focus:ring-4 focus:ring-teal-300
                   transform hover:scale-[1.02] active:scale-[0.98] transition-all shadow-lg"
          >
            <span class="flex items-center justify-center">
              <svg class="w-6 h-6 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
              Start Secure Wipe
            </span>
          </button>
        </div>
      </div>

    {:else if currentStep === 3}
      <!-- ================================================================ -->
      <!-- Step 4: Progress - Real-time Wipe Progress -->
      <!-- ================================================================ -->
      <div class="max-w-lg mx-auto">
        <h2 class="text-2xl font-bold text-gray-800 mb-4">
          {wipeComplete ? 'Wipe Complete!' : 'Wiping in Progress...'}
        </h2>

        <div class="bg-white rounded-xl shadow-lg p-6 space-y-5">
          <!-- Progress Ring + Percentage -->
          <div class="flex items-center justify-center">
            <div class="relative w-32 h-32">
              <svg class="w-32 h-32 transform -rotate-90" viewBox="0 0 100 100">
                <circle
                  class="text-gray-200"
                  stroke-width="8"
                  stroke="currentColor"
                  fill="transparent"
                  r="42"
                  cx="50"
                  cy="50"
                />
                <circle
                  class="{wipeComplete ? 'text-green-500' : 'text-teal-500'} transition-all duration-500"
                  stroke-width="8"
                  stroke-linecap="round"
                  stroke="currentColor"
                  fill="transparent"
                  r="42"
                  cx="50"
                  cy="50"
                  stroke-dasharray="{2 * Math.PI * 42}"
                  stroke-dashoffset="{2 * Math.PI * 42 * (1 - wipeProgress / 100)}"
                />
              </svg>
              <div class="absolute inset-0 flex items-center justify-center">
                <span class="text-3xl font-bold {wipeComplete ? 'text-green-600' : 'text-teal-600'}">{Math.round(wipeProgress)}%</span>
              </div>
            </div>
          </div>

          <!-- Pass Counter -->
          {#if totalPasses > 0}
            <div class="text-center">
              <span class="text-sm text-gray-500">Pass</span>
              <span class="text-lg font-semibold text-gray-700 ml-1">{currentPass} / {totalPasses}</span>
            </div>
          {/if}

          <!-- Phase Indicator -->
          {#if progressPhase}
            <div class="flex items-center justify-center space-x-2">
              <span class="w-2 h-2 rounded-full bg-teal-500 animate-pulse"></span>
              <span class="text-sm text-gray-600 capitalize">{progressPhase}</span>
            </div>
          {/if}

          <!-- Progress Bar -->
          <div class="relative">
            <div class="h-3 bg-gray-200 rounded-full overflow-hidden">
              <div
                style="width: {wipeProgress}%"
                class="h-full rounded-full transition-all duration-500 {wipeComplete ? 'bg-green-500' : 'bg-gradient-to-r from-teal-400 to-teal-600'}"
              ></div>
            </div>
          </div>

          <!-- Status Message -->
          {#if progressMessage}
            <p class="text-sm text-gray-600 text-center">{progressMessage}</p>
          {/if}

          <!-- Error Display -->
          {#if wipeError}
            <div class="p-4 bg-red-50 border border-red-200 rounded-lg">
              <p class="text-red-700 text-sm">{wipeError}</p>
            </div>
          {/if}

          <!-- Log Output -->
          <div bind:this={logContainer} class="bg-gray-900 rounded-lg p-4 h-40 overflow-y-auto font-mono text-xs">
            {#each wipeLog as log}
              <p class="text-green-400 leading-relaxed">{log}</p>
            {:else}
              <p class="text-gray-500">Initializing wipe process...</p>
            {/each}
          </div>

          <!-- Warning and Abort button while wiping -->
          {#if isWiping}
            <div class="flex flex-col items-center space-y-4">
              <div class="flex items-center justify-center text-amber-600 text-sm">
                <svg class="w-4 h-4 mr-2 animate-pulse" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
                </svg>
                Do not disconnect your device
              </div>
              <button
                onclick={abortWipe}
                disabled={isAborting}
                class="px-4 py-2 bg-red-600 hover:bg-red-700 disabled:bg-red-400 text-white text-sm font-medium rounded-lg transition-colors"
              >
                {#if isAborting}
                  Aborting...
                {:else}
                  Abort Wipe
                {/if}
              </button>
            </div>
          {/if}
        </div>
      </div>

    {:else if currentStep === 4}
      <!-- ================================================================ -->
      <!-- Step 5: Done - Success & Final Reset -->
      <!-- ================================================================ -->
      <div class="max-w-lg mx-auto">
        <div class="bg-white rounded-xl shadow-lg p-8 text-center">
          <!-- Success Icon -->
          <div class="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-6">
            <svg class="w-10 h-10 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
          </div>

          <h2 class="text-2xl font-bold text-gray-800 mb-2">Secure Wipe Complete!</h2>
          <p class="text-gray-600 mb-6">
            Your {deviceInfo.brand} {deviceInfo.model} has been securely wiped and is ready for trade-in or donation.
          </p>

          <!-- Stats Summary -->
          <div class="grid grid-cols-3 gap-4 mb-8">
            <div class="p-3 bg-teal-50 rounded-lg">
              <p class="text-2xl font-bold text-teal-600">{passes}</p>
              <p class="text-xs text-gray-500">Passes</p>
            </div>
            <div class="p-3 bg-teal-50 rounded-lg">
              <p class="text-2xl font-bold text-teal-600 capitalize">{wipeMode}</p>
              <p class="text-xs text-gray-500">Mode</p>
            </div>
            <div class="p-3 bg-green-50 rounded-lg">
              <p class="text-2xl font-bold text-green-600">✓</p>
              <p class="text-xs text-gray-500">Verified</p>
            </div>
          </div>

          <!-- Factory Reset Section -->
          <div class="text-left bg-amber-50 border border-amber-200 rounded-xl p-5 mb-6">
            <h3 class="font-semibold text-gray-800 mb-3 flex items-center">
              <svg class="w-5 h-5 mr-2 text-amber-600" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clip-rule="evenodd" />
              </svg>
              Final Step: Factory Reset
            </h3>

            <p class="text-sm text-gray-600 mb-3">
              <strong>Recommended:</strong> Perform a final factory reset to clear system caches and ensure a clean handoff.
            </p>

            <ol class="text-sm text-gray-600 space-y-1 ml-4 list-decimal">
              <li>Disconnect phone from USB</li>
              <li>Go to <strong>Settings</strong> on the phone</li>
              <li>Navigate to factory reset (see instructions below)</li>
              <li>Confirm the reset</li>
              <li>Phone is now safe to trade-in/sell!</li>
            </ol>
          </div>

          <!-- Brand-specific Instructions -->
          {#if resetInstructions.length > 0}
            <div class="text-left bg-blue-50 rounded-xl p-5 mb-6">
              <h3 class="font-semibold text-gray-800 mb-3 flex items-center">
                <svg class="w-5 h-5 mr-2 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
                </svg>
                Reset Instructions for {deviceInfo.brand}
              </h3>
              <ol class="text-sm text-gray-600 space-y-2">
                {#each resetInstructions.filter(i => i.trim()) as instruction, idx}
                  <li class="flex items-start">
                    <span class="w-5 h-5 rounded-full bg-blue-100 text-blue-600 text-xs flex items-center justify-center mr-2 flex-shrink-0 mt-0.5">{idx + 1}</span>
                    {instruction}
                  </li>
                {/each}
              </ol>
            </div>
          {/if}

          <!-- Final Checklist -->
          <div class="text-left bg-green-50 border border-green-200 rounded-xl p-5">
            <h3 class="font-semibold text-green-800 mb-3">Final Steps for Trade-In</h3>
            <p class="text-sm text-green-700 mb-3">Your device has been securely wiped. Complete these final steps:</p>
            <ol class="space-y-2 text-sm text-gray-600 ml-4 list-decimal">
              <li>Complete final factory reset (instructions above)</li>
              <li>Verify setup screen appears without asking for previous Google account</li>
              <li>Confirm no personal data, photos, or messages visible</li>
              <li>Remove SIM card</li>
              <li>Remove SD card (if applicable)</li>
              <li>Clean device and power off</li>
            </ol>
            <p class="text-xs text-green-600 mt-3 italic">✓ Device is now ready for trade-in, sale, or donation!</p>
          </div>

          <!-- Wipe Another Device -->
          <button
            onclick={resetWizard}
            class="mt-6 px-6 py-3 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-all"
          >
            Wipe Another Device
          </button>
        </div>
      </div>
    {/if}
  </div>

  <!-- Footer Navigation -->
  <footer class="bg-white border-t px-6 py-4 no-select">
    <div class="max-w-lg mx-auto flex justify-between items-center">
      <button
        onclick={prevStep}
        disabled={currentStep === 0 || isWiping}
        class="px-4 py-2 text-gray-600 hover:text-gray-800 disabled:opacity-50 disabled:cursor-not-allowed
               flex items-center transition-colors"
      >
        <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clip-rule="evenodd" />
        </svg>
        Back
      </button>

      <p class="text-xs text-gray-400 hidden sm:block">
        OnlyParams, a division of Ciphracore Systems LLC
      </p>

      {#if currentStep < 2}
        <button
          onclick={nextStep}
          disabled={!canProceed}
          class="px-6 py-2 bg-teal-600 text-white rounded-lg hover:bg-teal-700
                 disabled:opacity-50 disabled:cursor-not-allowed transition-all
                 flex items-center"
        >
          Next
          <svg class="w-4 h-4 ml-1" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" />
          </svg>
        </button>
      {:else if currentStep === 3 && wipeComplete}
        <button
          onclick={nextStep}
          class="px-6 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-all
                 flex items-center"
        >
          Continue
          <svg class="w-4 h-4 ml-1" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" />
          </svg>
        </button>
      {:else if currentStep === 3 && isWiping}
        <div class="px-6 py-2 text-teal-600 font-medium flex items-center">
          <svg class="animate-spin w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
          </svg>
          Wiping...
        </div>
      {:else}
        <div class="w-20"></div>
      {/if}
    </div>
  </footer>
</main>
