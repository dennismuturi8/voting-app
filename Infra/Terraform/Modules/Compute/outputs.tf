/*output "control_plane_ip" { value = aws_instance.nodes[0].private_ip }
output "worker_ips" { value = slice(aws_instance.nodes[*].private_ip, 1, 3) }
output "worker_instance_ids" {
  description = "IDs of worker instances"
  value       = aws_instance.nodes[*].id
}*/

# modules/compute/outputs.tf
output "control_plane_ip" { value = aws_instance.control_plane.private_ip }
output "worker_ips"        { value = aws_instance.workers[*].private_ip }
output "worker_instance_ids" {
  description = "IDs of worker instances"
  value       = aws_instance.workers[*].id
}


/*output "control_plane_ip" {
value = module.compute.control_plane_ip
}


output "worker_ips" {
value = module.compute.worker_ips
}*/

