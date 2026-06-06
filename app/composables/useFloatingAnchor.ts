import { computed, ref, type CSSProperties } from 'vue';

/**
 * A "virtual" floating anchor used to position Reka UI / Nuxt UI menus over
 * arbitrary DOM elements. The hook returns a style object you bind to a 0-size
 * trigger span; calling {@link openAt} moves that span to cover an element's
 * bounding rect so the popover/dropdown opens anchored to it.
 *
 * Keeps the rect set after close — Reka UI reads the trigger rect during
 * exit animation, so yanking it to display:none mid-animation makes the
 * menu flash to (0,0). The anchor stays invisible (pointer-events:none,
 * 0-size text) at the last position until the next call repositions it.
 */
export default function useFloatingAnchor() {
  const rect = ref<DOMRect | null>(null);

  const style = computed<CSSProperties>(() => {
    const r = rect.value;
    if (!r) return { display: 'none' };
    return {
      position: 'fixed',
      top: `${r.top}px`,
      left: `${r.left}px`,
      width: `${r.width}px`,
      height: `${r.height}px`,
      pointerEvents: 'none',
    };
  });

  function openAt(el: Element) {
    rect.value = el.getBoundingClientRect();
  }

  function reset() {
    rect.value = null;
  }

  return { style, openAt, reset };
}
