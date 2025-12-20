using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RayTracedSphere : MonoBehaviour
{
	public RayTracingMaterial material;

    // IMPORTANTE: Para efeitos relativísticos visíveis, use massas GIGANTESCAS!
    // Recomendação: massa ≥ 1e24 kg (ordem de magnitude de planetas/estrelas)
    // Exemplo: Terra ≈ 6e24 kg, Sol ≈ 2e30 kg
    // Com massas pequenas, o termo 8πG/(c⁴) pode ser zerado pela precisão do float.
    public float massa = 1.0f; 

	[SerializeField, HideInInspector] int materialObjectID;
	[SerializeField, HideInInspector] bool materialInitFlag;

	void OnValidate()
	{
		if (!materialInitFlag)
		{
			materialInitFlag = true;
			material.SetDefaultValues();
		}

		MeshRenderer renderer = GetComponent<MeshRenderer>();
		if (renderer != null)
		{
			if (materialObjectID != gameObject.GetInstanceID())
			{
				renderer.sharedMaterial = new Material(renderer.sharedMaterial);
				materialObjectID = gameObject.GetInstanceID();
			}
			renderer.sharedMaterial.color = material.colour;
		}
	}
}
