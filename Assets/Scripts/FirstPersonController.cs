using UnityEngine;

public class FirstPersonController : MonoBehaviour
{
    [Header("Movement Settings")]
    [SerializeField] float moveSpeed = 5f;
    [SerializeField] float mouseSensitivity = 2f;
    [SerializeField] float verticalLookLimit = 90f;

    [Header("Controls")]
    [SerializeField] KeyCode forwardKey = KeyCode.W;
    [SerializeField] KeyCode backwardKey = KeyCode.S;
    [SerializeField] KeyCode leftKey = KeyCode.A;
    [SerializeField] KeyCode rightKey = KeyCode.D;
    [SerializeField] KeyCode upKey = KeyCode.Space;
    [SerializeField] KeyCode downKey = KeyCode.LeftShift;

    private float xRotation = 0f;
    private Camera playerCamera;
    
    void Start()
    {
        playerCamera = GetComponent<Camera>();
        if (playerCamera == null)
            playerCamera = Camera.main;
            
        // Lock cursor to center of screen
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
    }

    void Update()
    {
        if (!Application.isPlaying) return;

        HandleMouseLook();
        HandleMovement();
        
        // Toggle cursor lock with Escape
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            if (Cursor.lockState == CursorLockMode.Locked)
            {
                Cursor.lockState = CursorLockMode.None;
                Cursor.visible = true;
            }
            else
            {
                Cursor.lockState = CursorLockMode.Locked;
                Cursor.visible = false;
            }
        }
    }

    void HandleMouseLook()
    {
        if (Cursor.lockState != CursorLockMode.Locked) return;

        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;

        // Rotate the camera vertically
        xRotation -= mouseY;
        xRotation = Mathf.Clamp(xRotation, -verticalLookLimit, verticalLookLimit);
        transform.localRotation = Quaternion.Euler(xRotation, 0f, 0f);

        // Rotate the player horizontally
        transform.parent.Rotate(Vector3.up * mouseX);
    }

    void HandleMovement()
    {
        Vector3 move = Vector3.zero;

        // Get input
        if (Input.GetKey(forwardKey)) move += transform.parent.forward;
        if (Input.GetKey(backwardKey)) move -= transform.parent.forward;
        if (Input.GetKey(leftKey)) move -= transform.parent.right;
        if (Input.GetKey(rightKey)) move += transform.parent.right;
        if (Input.GetKey(upKey)) move += Vector3.up;
        if (Input.GetKey(downKey)) move -= Vector3.up;

        // Apply movement
        if (move != Vector3.zero)
        {
            move = move.normalized * moveSpeed * Time.deltaTime;
            transform.parent.position += move;
        }
    }

    void OnGUI()
    {
        if (Cursor.lockState != CursorLockMode.Locked)
        {
            GUI.Label(new Rect(10, Screen.height - 40, 300, 20), "Press ESC to lock cursor and enable camera control");
        }
        else
        {
            GUI.Label(new Rect(10, Screen.height - 60, 300, 40), "WASD: Move | Mouse: Look | Space: Up | Shift: Down | ESC: Unlock cursor");
        }
    }
}
