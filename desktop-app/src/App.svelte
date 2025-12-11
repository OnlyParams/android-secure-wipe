<script>
  // SecureWipe Wizard - Main Application Component
  // OnlyParams, a division of Ciphracore Systems LLC

  import { onMount } from 'svelte';

  // Wizard step state
  let currentStep = 0;
  const steps = ['Prepare', 'Options', 'Confirm', 'Progress', 'Done'];

  // Device state
  let deviceConnected = false;
  let deviceInfo = { id: '', model: '', brand: '' };
  let storageInfo = { total: 0, available: 0 };

  // Wipe options state
  let wipeMode = 'quick';
  let doubleReset = false;
  let passes = 3;

  // Progress state
  let wipeProgress = 0;
  let wipeLog = [];
  let isWiping = false;

  // Computed ETA
  $: eta = wipeMode === 'quick' ? '~15 mins' : '1-3+ hrs';

  onMount(() => {
    console.log('SecureWipe Wizard initialized');
    // TODO: Check ADB connection on mount
  });

  function nextStep() {
    if (currentStep < steps.length - 1) {
      currentStep++;
    }
  }

  function prevStep() {
    if (currentStep > 0) {
      currentStep--;
    }
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
            class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium
                   {i === currentStep ? 'bg-teal-600 text-white' :
                    i < currentStep ? 'bg-teal-200 text-teal-800' : 'bg-gray-200 text-gray-500'}"
          >
            {i + 1}
          </span>
          <span class="ml-2 text-sm {i === currentStep ? 'text-teal-700 font-medium' : 'text-gray-500'}">
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
      <!-- Step 1: Prepare -->
      <div class="max-w-lg mx-auto">
        <h2 class="text-2xl font-bold text-gray-800 mb-4">Prepare Your Device</h2>
        <div class="bg-white rounded-lg shadow-md p-6 space-y-4">
          <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
            <div>
              <p class="font-medium text-gray-700">Device Connection</p>
              <p class="text-sm text-gray-500">
                {deviceConnected ? `${deviceInfo.brand} ${deviceInfo.model}` : 'No device detected'}
              </p>
            </div>
            <span class="w-3 h-3 rounded-full {deviceConnected ? 'bg-green-500' : 'bg-red-500'}"></span>
          </div>

          <button
            class="w-full py-3 px-4 bg-teal-600 text-white rounded-lg hover:bg-teal-700
                   focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 transition-all"
          >
            Check Connection
          </button>

          <div class="text-sm text-gray-600 space-y-2">
            <p class="font-medium">Before you start:</p>
            <ul class="list-disc list-inside space-y-1 text-gray-500">
              <li>Enable USB Debugging on your Android device</li>
              <li>Connect via USB cable</li>
              <li>Authorize this computer on your phone</li>
            </ul>
          </div>
        </div>
      </div>

    {:else if currentStep === 1}
      <!-- Step 2: Options (Using ModeCards design) -->
      <div class="max-w-md mx-auto p-6 bg-white rounded-lg shadow-md">
        <h2 class="text-2xl font-bold text-teal-800 mb-4 text-center">Choose Your Wipe Mode</h2>

        <div class="space-y-4">
          <!-- Quick Mode Card -->
          <div class="p-4 border-l-4 border-green-500 bg-green-50 rounded-r-md hover:shadow-md transition-all">
            <div class="flex items-center mb-2">
              <svg class="w-6 h-6 text-green-600 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" />
              </svg>
              <h3 class="font-semibold text-teal-800">Quick Wipe</h3>
            </div>
            <p class="text-sm text-gray-600 mb-2">Everyday shield: 3 passes x 1GB + resets = NIST-level peace. No one's chasing your old memes.</p>
            <p class="text-xs text-teal-600 font-medium">{wipeMode === 'quick' ? eta : '~15 mins'}</p>
            <label class="inline-flex items-center mt-2 cursor-pointer">
              <input type="radio" bind:group={wipeMode} value="quick" class="form-radio text-teal-600 rounded border-gray-300 focus:ring-teal-500" />
              <span class="ml-2 text-sm">Select</span>
            </label>
          </div>

          <!-- Full Mode Card -->
          <div class="p-4 border-l-4 border-teal-500 bg-teal-50 rounded-r-md hover:shadow-md transition-all">
            <div class="flex items-center mb-2">
              <svg class="w-6 h-6 text-teal-600 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" />
              </svg>
              <h3 class="font-semibold text-teal-800">Full Wipe</h3>
            </div>
            <p class="text-sm text-gray-600 mb-2">For 'just in case': Multi-pass 95% fill—overkill for most, but sleep-easy sure. (Unless state secrets—grab a shredder.)</p>
            <p class="text-xs text-teal-600 font-medium">{wipeMode === 'full' ? eta : '1-3+ hrs'}</p>
            <label class="inline-flex items-center mt-2 cursor-pointer">
              <input type="radio" bind:group={wipeMode} value="full" class="form-radio text-teal-600 rounded border-gray-300 focus:ring-teal-500" />
              <span class="ml-2 text-sm">Select</span>
            </label>
          </div>
        </div>

        <!-- Double Reset Toggle -->
        <div class="mt-6 p-4 bg-gray-50 rounded-md">
          <label class="flex items-center cursor-pointer">
            <input type="checkbox" bind:checked={doubleReset} class="rounded border-teal-500 text-teal-600 focus:ring-teal-500 w-4 h-4" />
            <span class="ml-2 text-sm font-medium text-teal-800">Double Factory Reset (Adds ~10-15 min for max security)</span>
          </label>
        </div>
      </div>

    {:else if currentStep === 2}
      <!-- Step 3: Confirm -->
      <div class="max-w-lg mx-auto">
        <h2 class="text-2xl font-bold text-gray-800 mb-4">Confirm Your Settings</h2>
        <div class="bg-white rounded-lg shadow-md p-6 space-y-4">
          <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
            <p class="text-yellow-800 font-medium">Warning: This action is irreversible</p>
            <p class="text-yellow-700 text-sm mt-1">All data on your device will be securely erased.</p>
          </div>

          <dl class="divide-y divide-gray-100">
            <div class="py-3 flex justify-between">
              <dt class="text-gray-500">Wipe Mode</dt>
              <dd class="text-gray-900 font-medium capitalize">{wipeMode}</dd>
            </div>
            <div class="py-3 flex justify-between">
              <dt class="text-gray-500">Double Reset</dt>
              <dd class="text-gray-900 font-medium">{doubleReset ? 'Yes' : 'No'}</dd>
            </div>
            <div class="py-3 flex justify-between">
              <dt class="text-gray-500">Estimated Time</dt>
              <dd class="text-gray-900 font-medium">{eta}</dd>
            </div>
          </dl>
        </div>
      </div>

    {:else if currentStep === 3}
      <!-- Step 4: Progress -->
      <div class="max-w-lg mx-auto">
        <h2 class="text-2xl font-bold text-gray-800 mb-4">Wiping in Progress</h2>
        <div class="bg-white rounded-lg shadow-md p-6 space-y-4">
          <div class="relative pt-1">
            <div class="flex mb-2 items-center justify-between">
              <span class="text-sm font-medium text-teal-700">Progress</span>
              <span class="text-sm font-medium text-teal-700">{wipeProgress}%</span>
            </div>
            <div class="overflow-hidden h-3 text-xs flex rounded-full bg-teal-100">
              <div
                style="width: {wipeProgress}%"
                class="shadow-none flex flex-col text-center whitespace-nowrap text-white justify-center bg-teal-600 transition-all duration-500"
              ></div>
            </div>
          </div>

          <div class="bg-gray-900 rounded-lg p-4 h-48 overflow-y-auto font-mono text-xs">
            {#each wipeLog as log}
              <p class="text-green-400">{log}</p>
            {:else}
              <p class="text-gray-500">Waiting to start...</p>
            {/each}
          </div>
        </div>
      </div>

    {:else if currentStep === 4}
      <!-- Step 5: Done -->
      <div class="max-w-lg mx-auto text-center">
        <div class="bg-white rounded-lg shadow-md p-8">
          <div class="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg class="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <h2 class="text-2xl font-bold text-gray-800 mb-2">Wipe Complete!</h2>
          <p class="text-gray-600 mb-6">Your device has been securely wiped and is ready for trade-in.</p>

          <div class="text-left bg-gray-50 rounded-lg p-4 text-sm">
            <p class="font-medium text-gray-700 mb-2">Next Steps:</p>
            <ul class="space-y-2 text-gray-600">
              <li class="flex items-center">
                <input type="checkbox" class="mr-2 rounded" />
                Perform factory reset from device settings
              </li>
              <li class="flex items-center">
                <input type="checkbox" class="mr-2 rounded" />
                Remove SIM card and SD card
              </li>
              <li class="flex items-center">
                <input type="checkbox" class="mr-2 rounded" />
                Sign out of all accounts
              </li>
            </ul>
          </div>
        </div>
      </div>
    {/if}
  </div>

  <!-- Footer Navigation -->
  <footer class="bg-white border-t px-6 py-4">
    <div class="max-w-lg mx-auto flex justify-between items-center">
      <button
        onclick={prevStep}
        disabled={currentStep === 0}
        class="px-4 py-2 text-gray-600 hover:text-gray-800 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Back
      </button>

      <p class="text-xs text-gray-500">
        Powered by OnlyParams, a division of Ciphracore Systems LLC
      </p>

      <button
        onclick={nextStep}
        disabled={currentStep === steps.length - 1}
        class="px-6 py-2 bg-teal-600 text-white rounded-lg hover:bg-teal-700
               disabled:opacity-50 disabled:cursor-not-allowed transition-all"
      >
        {currentStep === 2 ? 'Start Wipe' : 'Next'}
      </button>
    </div>
  </footer>
</main>
