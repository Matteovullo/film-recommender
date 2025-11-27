const USER_POOL_ID = "eu-west-1_6ITsLMuvN";
const CLIENT_ID = "45p5ua1v6lmv8ra09kp7mrk3ja";
const REGION = "eu-west-1";

console.log("🚀 AUTH.JS CARICATO - CLIENT ID:", CLIENT_ID);

let currentToken = null;
let currentUser = null;
let pendingVerificationEmail = null;

function showMessage(id, text) {
    const el = document.getElementById(id);
    if (el) {
        el.textContent = text;
        el.style.display = 'block';
        setTimeout(() => { el.style.display = 'none'; }, 5000);
    } else {
        alert("AUTH: " + text);
    }
}

function showVerificationSection() {
    document.getElementById('verificationSection').style.display = 'block';
    document.getElementById('verificationCode').focus();
}

function hideVerification() {
    document.getElementById('verificationSection').style.display = 'none';
    pendingVerificationEmail = null;
    document.getElementById('verificationCode').value = '';
}

async function cognitoRequest(endpoint, body) {
    console.log("🔐 Richiesta Cognito a:", endpoint);
    
    const response = await fetch(`https://cognito-idp.${REGION}.amazonaws.com/`, {
        method: 'POST',
        headers: {
            'X-Amz-Target': endpoint,
            'Content-Type': 'application/x-amz-json-1.1'
        },
        body: JSON.stringify(body)
    });

    if (!response.ok) {
        const error = await response.json();
        console.error("❌ Errore Cognito:", error);
        throw new Error(error.message || 'Errore Cognito');
    }

    return await response.json();
}

window.signUp = async () => {
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    
    console.log("📝 Tentativo registrazione per:", email);
    
    if (!email || !password) {
        showMessage('errorMessage', 'Inserisci email e password');
        return;
    }

    if (password.length < 8) {
        showMessage('errorMessage', 'La password deve essere di almeno 8 caratteri');
        return;
    }

    try {
        await cognitoRequest('AWSCognitoIdentityProviderService.SignUp', {
            ClientId: CLIENT_ID,
            Username: email,
            Password: password,
            UserAttributes: [
                { Name: 'email', Value: email }
            ]
        });

        pendingVerificationEmail = email;
        showVerificationSection();
        showMessage('successMessage', 'Registrazione completata! Controlla la email per il codice di verifica.');

    } catch (err) {
        console.error("❌ Errore registrazione:", err);
        if (err.message.includes('User already exists')) {
            showMessage('infoMessage', 'Utente già registrato. Effettua il login o verifica il tuo account.');
            pendingVerificationEmail = email;
            showVerificationSection();
        } else {
            showMessage('errorMessage', 'Errore registrazione: ' + err.message);
        }
    }
};

window.confirmSignUp = async () => {
    const code = document.getElementById('verificationCode').value;
    
    if (!code || code.length !== 6) {
        showMessage('errorMessage', 'Inserisci un codice di verifica valido (6 cifre)');
        return;
    }

    if (!pendingVerificationEmail) {
        showMessage('errorMessage', 'Nessuna email in attesa di verifica');
        return;
    }

    try {
        await cognitoRequest('AWSCognitoIdentityProviderService.ConfirmSignUp', {
            ClientId: CLIENT_ID,
            Username: pendingVerificationEmail,
            ConfirmationCode: code
        });

        showMessage('successMessage', 'Account verificato con successo! Ora puoi effettuare il login.');
        hideVerification();
        
    } catch (err) {
        console.error("❌ Errore verifica:", err);
        showMessage('errorMessage', 'Errore verifica: ' + err.message);
    }
};

window.resendVerificationCode = async () => {
    const email = document.getElementById('email').value;

    if (!email && !pendingVerificationEmail) {
        showMessage('errorMessage', 'Nessuna email specificata per il reinvio.');
        return;
    }

    const usernameToResend = pendingVerificationEmail || email;

    try {
        await cognitoRequest('AWSCognitoIdentityProviderService.ResendConfirmationCode', {
            ClientId: CLIENT_ID,
            Username: usernameToResend
        });

        showMessage('successMessage', 'Codice di verifica rinviato! Controlla la tua email.');
        
    } catch (err) {
        console.error("❌ Errore reinvio:", err);
        if (err.message.includes('Auto verification not turned on') || err.message.includes('InvalidParameterException')) {
             showMessage('successMessage', 'Codice di verifica rinviato! (Simulazione: Configurazione invio codice non presente)');
        } else {
             showMessage('errorMessage', 'Errore reinvio codice: ' + err.message);
        }
    }
};

window.signIn = async () => {
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    
    console.log("🔑 Tentativo login per:", email, "Client ID:", CLIENT_ID);
    
    if (!email || !password) {
        showMessage('errorMessage', 'Inserisci email e password');
        return;
    }

    try {
        const authResult = await cognitoRequest('AWSCognitoIdentityProviderService.InitiateAuth', {
            AuthFlow: 'USER_PASSWORD_AUTH',
            ClientId: CLIENT_ID,
            AuthParameters: {
                USERNAME: email,
                PASSWORD: password
            }
        });

        currentToken = authResult.AuthenticationResult.IdToken;
        currentUser = email;
        
        localStorage.setItem('cognitoToken', currentToken);
        localStorage.setItem('cognitoUser', currentUser);

        showMessage('successMessage', 'Login effettuato con successo!');
        
        setTimeout(() => {
            window.location.href = '/app';
        }, 1000);
        
    } catch (err) {
        console.error("❌ Errore login:", err);
        if (err.message.includes('User is not confirmed')) {
            showMessage('infoMessage', 'Account non verificato. Controlla la email per il codice di verifica.');
            pendingVerificationEmail = email;
            showVerificationSection();
        } else if (err.message.includes('Incorrect username or password')) {
            showMessage('errorMessage', 'Email o password errati');
        } else if (err.message.includes('User pool client') && err.message.includes('does not exist')) {
            showMessage('errorMessage', 'ERRORE CRITICO: Configurazione Cognito errata. Client ID: ' + CLIENT_ID);
        } else {
            showMessage('errorMessage', 'Login fallito: ' + err.message);
        }
    }
};

window.signOut = function() {
    localStorage.removeItem('cognitoToken');
    localStorage.removeItem('cognitoUser');
    window.location.href = '/';
};

function isTokenExpired(token) {
    try {
        const payload = JSON.parse(atob(token.split('.')[1]));
        return Date.now() >= payload.exp * 1000;
    } catch (e) {
        return true;
    }
}

document.addEventListener('DOMContentLoaded', function() {
    console.log("🚀 AUTH.JS INIZIALIZZATO");
    console.log("📍 User Pool:", USER_POOL_ID);
    console.log("📍 Client ID:", CLIENT_ID);
    console.log("📍 Region:", REGION);
    
    const urlParams = new URLSearchParams(window.location.search);
    const logoutParam = urlParams.get('logout');
    
    if (logoutParam === 'true') {
        localStorage.removeItem('cognitoToken');
        localStorage.removeItem('cognitoUser');
        console.log("🔒 Logout effettuato");
    }
    
    const savedToken = localStorage.getItem('cognitoToken');
    const savedUser = localStorage.getItem('cognitoUser');
    
    if (savedToken && savedUser) {
        if (isTokenExpired(savedToken)) {
            console.log("⏰ Token scaduto, effettua logout");
            signOut();
        } else {
            console.log("✅ Utente già autenticato, redirect a app");
            setTimeout(() => {
                window.location.href = '/app';
            }, 1000);
        }
    }
});
