(() => {
    'use strict';

    const body = document.body;
    const form = document.querySelector('[data-login-form]');
    if (!form) return;
    const provider = body.dataset.botProvider || 'none';
    const siteKey = body.dataset.botSiteKey || '';
    const tokenInput = form.querySelector('[data-bot-token]');
    const errorBox = form.querySelector('[data-bot-error]');
    let submitting = false;

    const showError = (message) => {
        if (!errorBox) return;
        errorBox.textContent = message;
        errorBox.hidden = false;
    };

    const submitWithToken = (token) => {
        if (!token || !tokenInput) {
            showError('Bot verification is required before signing in.');
            return;
        }
        tokenInput.value = token;
        submitting = true;
        form.submit();
    };

    form.addEventListener('submit', (event) => {
        if (submitting || provider === 'none') return;
        event.preventDefault();
        if (provider === 'recaptcha_v3') {
            if (!window.grecaptcha || !siteKey) {
                showError('reCAPTCHA could not be loaded. Check the Dashboard network connection.');
                return;
            }
            window.grecaptcha.ready(() => {
                window.grecaptcha.execute(siteKey, { action: 'login' })
                    .then(submitWithToken)
                    .catch(() => showError('reCAPTCHA verification failed. Please try again.'));
            });
            return;
        }
        const token = form.querySelector('[name="cf-turnstile-response"]')?.value || '';
        submitWithToken(token);
    });
})();
