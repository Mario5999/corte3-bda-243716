const API_URL = 'http://localhost:3000/api';

// State
let session = { id: null, role: null, label: null };

// DOM Elements
const els = {
    userSelector: document.getElementById('userSelector'),
    loginBtn: document.getElementById('loginBtn'),
    logoutBtn: document.getElementById('logoutBtn'),
    authControls: document.querySelector('.auth-controls'),
    currentUserDisplay: document.getElementById('currentUserDisplay'),
    userBadge: document.getElementById('userBadge'),
    mainContent: document.getElementById('mainContent'),
    navItems: document.querySelectorAll('.sidebar li'),
    views: document.querySelectorAll('.view'),
    
    // Mascotas View
    searchInput: document.getElementById('searchInput'),
    searchBtn: document.getElementById('searchBtn'),
    mascotasTable: document.querySelector('#mascotasTable tbody'),
    
    // Vacunacion View
    loadVacunacionBtn: document.getElementById('loadVacunacionBtn'),
    applyVaccineBtn: document.getElementById('applyVaccineBtn'),
    vacunacionTable: document.querySelector('#vacunacionTable tbody'),
};

// Utils
function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

function getHeaders() {
    return {
        'Content-Type': 'application/json',
        'x-user-id': session.id,
        'x-user-role': session.role
    };
}

// Auth
els.loginBtn.addEventListener('click', () => {
    const val = els.userSelector.value;
    if (!val) return showToast('Selecciona un usuario', 'error');
    
    const [id, role] = val.split('|');
    const label = els.userSelector.options[els.userSelector.selectedIndex].text;
    
    session = { id, role, label };
    
    els.authControls.classList.add('hidden');
    els.currentUserDisplay.classList.remove('hidden');
    els.userBadge.textContent = `${label} (${role})`;
    els.mainContent.classList.remove('hidden');
    
    showToast(`Sesión iniciada como ${label}`);
    loadMascotas(); // default view
});

els.logoutBtn.addEventListener('click', () => {
    session = { id: null, role: null, label: null };
    els.authControls.classList.remove('hidden');
    els.currentUserDisplay.classList.add('hidden');
    els.mainContent.classList.add('hidden');
    els.mascotasTable.innerHTML = '';
    els.vacunacionTable.innerHTML = '';
});

// Navigation
els.navItems.forEach(item => {
    item.addEventListener('click', () => {
        els.navItems.forEach(nav => nav.classList.remove('active'));
        item.classList.add('active');
        
        const viewId = `view-${item.dataset.view}`;
        els.views.forEach(view => {
            view.classList.add('hidden');
            if (view.id === viewId) view.classList.remove('hidden');
        });
        
        if (item.dataset.view === 'vacunacion') loadVacunacion();
    });
});

// Mascotas
async function loadMascotas() {
    const search = els.searchInput.value;
    try {
        const url = search ? `${API_URL}/mascotas?search=${encodeURIComponent(search)}` : `${API_URL}/mascotas`;
        const res = await fetch(url, { headers: getHeaders() });
        
        if (!res.ok) throw new Error(await res.text());
        const data = await res.json();
        
        els.mascotasTable.innerHTML = '';
        data.forEach(m => {
            els.mascotasTable.innerHTML += `
                <tr>
                    <td>#${m.id}</td>
                    <td>${m.nombre}</td>
                    <td>${m.especie}</td>
                </tr>
            `;
        });
        if (data.length === 0) {
            els.mascotasTable.innerHTML = `<tr><td colspan="3">No se encontraron mascotas</td></tr>`;
        }
    } catch (err) {
        showToast('Error cargando mascotas o permisos denegados', 'error');
        console.error(err);
    }
}

els.searchBtn.addEventListener('click', loadMascotas);

// Vacunacion
async function loadVacunacion() {
    try {
        const res = await fetch(`${API_URL}/vacunacion-pendiente`, { headers: getHeaders() });
        if (!res.ok) {
             const errText = await res.text();
             throw new Error(errText.includes('permission denied') ? 'Permisos insuficientes para ver esta tabla.' : 'Error al cargar');
        }
        
        const data = await res.json();
        els.vacunacionTable.innerHTML = '';
        data.forEach(v => {
            const badgeClass = v.prioridad === 'NUNCA_VACUNADA' ? 'error' : '';
            els.vacunacionTable.innerHTML += `
                <tr>
                    <td><strong>${v.nombre}</strong><br><small>${v.nombre_dueno}</small></td>
                    <td>${v.especie}</td>
                    <td>${v.fecha_ultima_vacuna ? new Date(v.fecha_ultima_vacuna).toLocaleDateString() : 'Ninguna'}</td>
                    <td><span class="user-badge ${badgeClass}">${v.prioridad}</span></td>
                </tr>
            `;
        });
        showToast('Datos cargados (Revisa la consola del backend para ver el hit del caché)');
    } catch (err) {
        showToast(err.message, 'error');
        console.error(err);
    }
}

els.loadVacunacionBtn.addEventListener('click', loadVacunacion);

// Simular la aplicación de una vacuna
els.applyVaccineBtn.addEventListener('click', async () => {
    if (session.role !== 'vet_role' && session.role !== 'admin_role') {
        return showToast('Solo los veterinarios o admins pueden aplicar vacunas', 'error');
    }
    
    try {
        const res = await fetch(`${API_URL}/vacunas`, {
            method: 'POST',
            headers: getHeaders(),
            body: JSON.stringify({
                mascota_id: 1, // Firulais
                vacuna_id: 1,  // Antirrábica
                fecha_aplicacion: new Date().toISOString().split('T')[0],
                costo_cobrado: 350.00
            })
        });
        
        if (!res.ok) throw new Error(await res.text());
        
        showToast('Vacuna aplicada con éxito a Firulais. Caché invalidado.');
        loadVacunacion(); // Recargar la tabla
    } catch (err) {
        showToast('Error al aplicar vacuna: ' + err.message, 'error');
        console.error(err);
    }
});
