<template>
  <div class="ChatBubble">
    <svg
      width="13"
      height="14"
      fill="var(--chat-bubble-bg)"
    >
      <path d="M6 .246c-.175 5.992-1.539 8.89-5.5 13.5 6.117.073 9.128-.306 12.5-3L6 .246Z"></path>
    </svg>
    <span>
      <slot />
    </span>
  </div>
</template>

<style scoped>
.ChatBubble {
  margin: 0 0 0 4px;
  position: relative;
  --chat-bubble-bg: color-mix(in oklab, var(--ui-primary) 12%, var(--ui-bg));
}

.ChatBubble span {
  background-color: var(--chat-bubble-bg);
  color: var(--ui-primary);
  font-size: 12px;
  border-radius: 10px;
  padding: 5px 10px;
  display: block;
  width: fit-content;
}

.ChatBubble svg {
  position: absolute;
  left: -5.5px;
  bottom: 0.246px;
}
</style>
