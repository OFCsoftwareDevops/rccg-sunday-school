(() => {
  if (!window.appConfig) {
    console.error("config.js failed to load");
    return;
  }

  const { playStore, appStore } = window.appConfig.stores;

  const ua = navigator.userAgent || navigator.vendor || window.opera;
  const isIOS = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
  const isAndroid = /android/i.test(ua);

  const storeSection = document.getElementById("store-section");
  const highlightArea = document.getElementById("highlight-area");

  function createStoreButton(url, badge, altText) {
    const anchor = document.createElement("a");

    anchor.href = url;
    anchor.target = "_blank";
    anchor.rel = "noopener noreferrer";
    anchor.className = "store-btn";

    const image = document.createElement("img");
    image.src = badge;
    image.alt = altText;

    anchor.appendChild(image);

    return anchor;
  }

  const androidButton = createStoreButton(
    playStore.url,
    playStore.badge,
    "Get it on Google Play"
  );

  const iosButton = createStoreButton(
    appStore.url,
    appStore.badge,
    "Download on the App Store"
  );

  if (isAndroid) {
    highlightArea.appendChild(androidButton);
    storeSection.appendChild(iosButton);
  } else if (isIOS) {
    highlightArea.appendChild(iosButton);
    storeSection.appendChild(androidButton);
  } else {
    storeSection.appendChild(androidButton);
    storeSection.appendChild(iosButton);
  }
})();
