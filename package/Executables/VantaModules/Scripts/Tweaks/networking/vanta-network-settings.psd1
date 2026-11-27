@{
    Name        = 'Apply Vanta Network Settings'
    Description = 'Applies the Vanta network adapter defaults through the DefaultVantaNetwork toggle. It turns off adapter power-saving features such as Green Ethernet and DMA coalescing for steadier latency, which slightly raises idle power use on laptops.'
    Toggle      = @(
        @{ Name = 'DefaultVantaNetwork'; State = 'Enable' }
    )
}
