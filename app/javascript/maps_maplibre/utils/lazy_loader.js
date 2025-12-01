/**
 * Lazy loader for heavy map layers
 * Reduces initial bundle size by loading layers on demand
 */
export class LazyLoader {
  constructor() {
    this.cache = new Map()
    this.loading = new Map()
  }

  /**
   * Load layer class dynamically
   * @param {string} name - Layer name (e.g., 'fog', 'scratch')
   * @returns {Promise<Class>}
   */
  async loadLayer(name) {
    // Return cached
    if (this.cache.has(name)) {
      return this.cache.get(name)
    }

    // Wait for loading
    if (this.loading.has(name)) {
      return this.loading.get(name)
    }

    // Start loading
    const loadPromise = this.#load(name)
    this.loading.set(name, loadPromise)

    try {
      const LayerClass = await loadPromise
      this.cache.set(name, LayerClass)
      this.loading.delete(name)
      return LayerClass
    } catch (error) {
      this.loading.delete(name)
      throw error
    }
  }

  async #load(name) {
    const paths = {
      'fog': () => import('../layers/fog_layer.js'),
      'scratch': () => import('../layers/scratch_layer.js')
    }

    const loader = paths[name]
    if (!loader) {
      throw new Error(`Unknown layer: ${name}`)
    }

    const module = await loader()
    return module[this.#getClassName(name)]
  }

  #getClassName(name) {
    // fog -> FogLayer, scratch -> ScratchLayer
    return name.charAt(0).toUpperCase() + name.slice(1) + 'Layer'
  }

  /**
   * Preload layers
   * @param {string[]} names
   */
  async preload(names) {
    return Promise.all(names.map(name => this.loadLayer(name)))
  }

  clear() {
    this.cache.clear()
    this.loading.clear()
  }
}

export const lazyLoader = new LazyLoader()
