<script lang="ts">
  import NotifyStore from '../stores/notifyStore';

  function variantClass(type: string) {
    switch (type) {
      case 'success':
        return 'notify-success';
      case 'error':
        return 'notify-error';
      case 'warning':
        return 'notify-warning';
      case 'info':
      case 'inform':
        return 'notify-info';
      default:
        return 'notify-primary';
    }
  }
</script>

<div class="notify-wrap pointer-events-none">
  {#each $NotifyStore as item (item.id)}
    <div class="notify-item {variantClass(item.type)}">
      <div class="notify-dot"></div>
      <p>{item.message}</p>
    </div>
  {/each}
</div>

<style>
  .notify-wrap {
    position: fixed;
    right: 1.5rem;
    top: 1.2rem;
    z-index: 1001;
    display: flex;
    flex-direction: column;
    gap: 0.65rem;
    width: 360px;
    max-width: 32vw;
  }

  .notify-item {
    display: flex;
    align-items: center;
    gap: 10px;
    color: #eff8ff;
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 9px;
    padding: 10px 12px;
    font-size: 14px;
    background: rgba(8, 12, 18, 0.86);
    box-shadow: 0 0 16px rgba(0, 0, 0, 0.35);
    animation: pfNotifyIn 220ms ease-out;
  }

  .notify-item p {
    margin: 0;
    line-height: 1.2;
  }

  .notify-dot {
    width: 9px;
    height: 9px;
    border-radius: 999px;
    background: var(--notify-color, #00d9ff);
    box-shadow: 0 0 10px var(--notify-color, #00d9ff);
    flex: 0 0 auto;
  }

  .notify-primary { --notify-color: #00d9ff; }
  .notify-success { --notify-color: #1ccf8f; }
  .notify-error { --notify-color: #ff5a5a; }
  .notify-warning { --notify-color: #ffbf47; }
  .notify-info { --notify-color: #7da6ff; }

  @keyframes pfNotifyIn {
    from { transform: translateX(24px); opacity: 0; }
    to { transform: translateX(0); opacity: 1; }
  }
</style>
