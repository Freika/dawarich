export const createConsumer = () => ({
  subscriptions: { create: () => ({ unsubscribe() {}, perform() {} }) },
})
